#!/usr/bin/env bash
# publish-next.sh [count]
# Zennへの日次ドリップ公開ドライバ。既定 count=2（Zenn上限の観測値に合わせる）。
#
# Zennには投稿数上限があり、超過分は「デプロイされませんでした」と黙って保留される。
# そこで本スクリプトは次の順で「実際に公開されるまで」を面倒みる:
#   1. STUCK を最優先で再デプロイ
#      = published:true なのに Zenn で未公開の記事（過去に上限で弾かれた分）。
#        publish.sh <slug> --redeploy で末尾改行トグルにより確実に再送する。
#   2. 残り枠で下書き(published:false)を公開
#      = protocol-lab と protocol-in-code を交互に（lab→in-code→…）、各シリーズ内は
#        Lab番号 / トラック順→NN順。
#   3. いずれも publish.sh が「push したが Zen 未公開」(exit 3) を返したら、その日は
#      上限に達したと判断して即停止する（これ以上 push しても保留が増えるだけ）。
#
# 例: ./scripts/publish-next.sh 2
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

count="${1:-2}"
case "$count" in ''|*[!0-9]*) die "count は整数で指定してください: $count";; esac

# Zennの実公開一覧（真実）を1回だけ取得。取得できなければ STUCK 判定ができないので中断。
live="$(zenn_live_slugs)" || die "Zenn公開API取得に失敗（ネットワーク/jq）。突合できないため中止。"

is_true()  { [ "$(article_published_state "$1")" = "true"  ]; }
is_draft() { [ "$(article_published_state "$1")" = "false" ]; }
is_live()  { printf '%s\n' "$live" | grep -qx -- "$1"; }

# --- STUCK: published:true だが未公開（=再デプロイ対象）をコース順に集める ----
# lab → in-code → その他(one-off) の順。各シリーズ内は NN 昇順。
collect_ordered() {  # collect_ordered <mode: stuck|draft>
  local mode="$1" f slug nn
  # protocol-lab-*（NN順）
  for f in "$ARTICLES_DIR"/protocol-lab-*.md; do
    [ -e "$f" ] || continue
    slug="$(basename "$f" .md)"
    if [ "$mode" = stuck ]; then is_true "$f" && ! is_live "$slug" || continue
    else is_draft "$f" || continue; fi
    nn="$(printf '%s' "$slug" | grep -oE '[0-9]+$' || echo 999)"
    printf '%s\t%s\t%s\n' "0" "$nn" "$slug"
  done
  # protocol-in-code-*（トラック順→NN順）
  local ti=1 track
  for track in $CODE_TRACK_ORDER; do
    for f in "$ARTICLES_DIR"/protocol-in-code-"$track"-*.md; do
      [ -e "$f" ] || continue
      slug="$(basename "$f" .md)"
      if [ "$mode" = stuck ]; then is_true "$f" && ! is_live "$slug" || continue
      else is_draft "$f" || continue; fi
      nn="$(printf '%s' "$slug" | grep -oE '[0-9]+$' || echo 999)"
      printf '%s\t%02d%03d\t%s\n' "1" "$ti" "$nn" "$slug"
    done
    ti=$((ti + 1))
  done
  # その他（series以外の one-off。stuckのみ対象。draftは対象外）
  if [ "$mode" = stuck ]; then
    for f in "$ARTICLES_DIR"/*.md; do
      [ -e "$f" ] || continue
      slug="$(basename "$f" .md)"
      case "$slug" in protocol-lab-*|protocol-in-code-*) continue;; esac
      is_true "$f" && ! is_live "$slug" || continue
      printf '%s\t%s\t%s\n' "2" "$slug" "$slug"
    done
  fi
}

stuck=(); while IFS= read -r s; do [ -n "$s" ] && stuck+=("$s"); done < <(collect_ordered stuck | sort | cut -f3)

# --- 下書きを lab/in-code 交互に並べる ------------------------------------
lab_drafts=(); code_drafts=()
while IFS= read -r s; do [ -n "$s" ] && lab_drafts+=("$s"); done  < <(collect_ordered draft | awk -F'\t' '$1==0' | sort | cut -f3)
while IFS= read -r s; do [ -n "$s" ] && code_drafts+=("$s"); done < <(collect_ordered draft | awk -F'\t' '$1==1' | sort | cut -f3)

draft_queue=(); li=0; ci=0; turn="lab"
while [ "$li" -lt "${#lab_drafts[@]}" ] || [ "$ci" -lt "${#code_drafts[@]}" ]; do
  if [ "$turn" = lab ]; then
    if   [ "$li" -lt "${#lab_drafts[@]}" ];  then draft_queue+=("${lab_drafts[$li]}");  li=$((li+1))
    elif [ "$ci" -lt "${#code_drafts[@]}" ]; then draft_queue+=("${code_drafts[$ci]}"); ci=$((ci+1)); fi
    turn="code"
  else
    if   [ "$ci" -lt "${#code_drafts[@]}" ]; then draft_queue+=("${code_drafts[$ci]}"); ci=$((ci+1))
    elif [ "$li" -lt "${#lab_drafts[@]}" ];  then draft_queue+=("${lab_drafts[$li]}");  li=$((li+1)); fi
    turn="lab"
  fi
done

total_waiting=$(( ${#stuck[@]} + ${#draft_queue[@]} ))
if [ "$total_waiting" -eq 0 ]; then
  log "公開待ちはありません（STUCK 0 / 下書き 0）"
  notify "✅ Zenn: 公開待ちの記事はありません"
  exit 0
fi

log "STUCK(再デプロイ) ${#stuck[@]}本 / 下書き ${#draft_queue[@]}本。今回は最大 ${count}本を公開します。"
[ "${#stuck[@]}" -gt 0 ] && log "STUCK優先: ${stuck[*]}"

# --- 公開ループ: STUCK → 下書き。上限(exit 3)に当たったら即停止 -----------
published=0; stopped=0
attempt() {  # attempt <slug> [--redeploy]
  local slug="$1" flag="${2:-}" rc=0
  if [ "${DRY_RUN:-0}" = "1" ]; then
    log "→ [DRY] 公開: $slug ${flag}"
    published=$((published + 1))
    return
  fi
  log "→ 公開: $slug ${flag}"
  set +e
  "$SCRIPTS_DIR/publish.sh" "$slug" $flag
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    published=$((published + 1))
  elif [ "$rc" -eq 3 ]; then
    log "投稿数上限に達したと判断。本日はここで停止（残りは翌日以降に再試行）。"
    stopped=1
  else
    die "publish.sh が異常終了 (rc=$rc): $slug"
  fi
}

for slug in "${stuck[@]}"; do
  [ "$published" -lt "$count" ] || break
  attempt "$slug" --redeploy
  [ "$stopped" -eq 1 ] && break
done
if [ "$stopped" -eq 0 ]; then
  for slug in "${draft_queue[@]}"; do
    [ "$published" -lt "$count" ] || break
    attempt "$slug"
    [ "$stopped" -eq 1 ] && break
  done
fi

remaining=$(( total_waiting - published ))
log "今回 ${published}本 公開確認。残り ${remaining}本（STUCK含む。翌日の実行で継続）。"
