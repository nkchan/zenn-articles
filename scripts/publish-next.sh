#!/usr/bin/env bash
# publish-next.sh [count]
# 下書き(published:false)を <count> 本だけ publish.sh で公開する。既定 count=1。
# Zennの1日公開上限（観測で約2本/日）に合わせて「1日1〜2本」を回す運用を想定。
#
# シリーズ配分: protocol-lab と protocol-in-code の下書きを交互に公開する
# （lab → in-code → lab …）。片方の下書きが尽きたら残りの枠はもう一方に回す。
#   - protocol-lab-*       は Lab番号(slug末尾NN)順
#   - protocol-in-code-*   は CODE_TRACK_ORDER のトラック順 → NN順（コース順を維持）
#
# 例: ./scripts/publish-next.sh 2   # 次の下書き2本（lab 1 + in-code 1）を公開
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

count="${1:-1}"
case "$count" in ''|*[!0-9]*) die "count は整数で指定してください: $count";; esac

# 下書き判定: frontmatter先頭ブロックの published を見る。
is_draft() {
  local f="$1" st
  st="$(awk 'NR==1&&$0=="---"{fm=1;next} fm&&/^---[[:space:]]*$/{exit} fm&&/^published:/{gsub(/[[:space:]]/,"",$2);print $2;exit}' FS=: "$f")"
  [ "$st" = "false" ]
}

# --- protocol-lab の下書きを NN 昇順に集める --------------------------------
lab_drafts=()
while IFS= read -r _slug; do lab_drafts+=("$_slug"); done < <(
  for f in "$ARTICLES_DIR"/protocol-lab-*.md; do
    [ -e "$f" ] || continue
    is_draft "$f" || continue
    slug="$(basename "$f" .md)"
    nn="$(printf '%s' "$slug" | grep -oE '[0-9]+$' || echo 999)"
    printf '%s\t%s\n' "$nn" "$slug"
  done | sort -n | cut -f2
)

# --- protocol-in-code の下書きをトラック順 → NN順に集める --------------------
code_drafts=()
for track in $CODE_TRACK_ORDER; do
  while IFS= read -r _slug; do code_drafts+=("$_slug"); done < <(
    for f in "$ARTICLES_DIR"/protocol-in-code-"$track"-*.md; do
      [ -e "$f" ] || continue
      is_draft "$f" || continue
      slug="$(basename "$f" .md)"
      # slug末尾NN（ゼロ埋め）で昇順
      nn="$(printf '%s' "$slug" | grep -oE '[0-9]+$' || echo 999)"
      printf '%s\t%s\n' "$nn" "$slug"
    done | sort -n | cut -f2
  )
done

total_waiting=$(( ${#lab_drafts[@]} + ${#code_drafts[@]} ))
if [ "$total_waiting" -eq 0 ]; then
  log "公開待ちの下書きはありません（全て公開済み）"
  notify "✅ Zenn: 公開待ちの下書きはありません"
  exit 0
fi

log "公開待ち: lab ${#lab_drafts[@]}本 / in-code ${#code_drafts[@]}本。今回は最大 ${count}本を交互に公開します。"

published=0
li=0
ci=0
turn="lab"   # lab から始めて交互に
while [ "$published" -lt "$count" ]; do
  slug=""
  if [ "$turn" = "lab" ]; then
    if [ "$li" -lt "${#lab_drafts[@]}" ]; then
      slug="${lab_drafts[$li]}"; li=$((li + 1))
    elif [ "$ci" -lt "${#code_drafts[@]}" ]; then
      slug="${code_drafts[$ci]}"; ci=$((ci + 1))
    fi
    turn="code"
  else
    if [ "$ci" -lt "${#code_drafts[@]}" ]; then
      slug="${code_drafts[$ci]}"; ci=$((ci + 1))
    elif [ "$li" -lt "${#lab_drafts[@]}" ]; then
      slug="${lab_drafts[$li]}"; li=$((li + 1))
    fi
    turn="lab"
  fi
  [ -n "$slug" ] || break   # 両シリーズとも尽きた
  log "→ 公開: $slug"
  "$SCRIPTS_DIR/publish.sh" "$slug"
  published=$((published + 1))
done

remaining=$(( total_waiting - published ))
log "今回 ${published}本 公開。残り下書き ${remaining}本（lab $(( ${#lab_drafts[@]} - li )) / in-code $(( ${#code_drafts[@]} - ci )))。"
