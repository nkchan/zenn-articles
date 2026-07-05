#!/usr/bin/env bash
# sync.sh — メインパイプライン（cron 週1想定）。
#   1. protocol-lab を clone / pull
#   2. labs/*.md のうち converted.json に無い最初の1件を選ぶ（ファイル名順）
#   3. 無ければ「全Lab変換済み」を通知して終了
#   4. convert.sh で変換
#   5. frontmatter検証。壊れていたら1回だけリトライ、それでもダメなら通知して終了（pushしない）
#   6. converted.json 更新 → commit → push
#   7. 「下書き作成」を Telegram 通知
# 1回の実行で変換するのは必ず1記事まで。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

command -v jq  >/dev/null 2>&1 || die "jq が必要です"
command -v git >/dev/null 2>&1 || die "git が必要です"

# --- 1. protocol-lab を clone or pull ------------------------------------
mkdir -p "$WORK_DIR"
if [ -d "$LAB_CLONE_DIR/.git" ]; then
  log "protocol-lab を pull: $LAB_CLONE_DIR"
  git -C "$LAB_CLONE_DIR" fetch --quiet origin "$PROTOCOL_LAB_BRANCH"
  git -C "$LAB_CLONE_DIR" checkout --quiet "$PROTOCOL_LAB_BRANCH"
  git -C "$LAB_CLONE_DIR" reset --hard --quiet "origin/$PROTOCOL_LAB_BRANCH"
else
  log "protocol-lab を clone: $PROTOCOL_LAB_REPO -> $LAB_CLONE_DIR"
  git clone --quiet --branch "$PROTOCOL_LAB_BRANCH" "$PROTOCOL_LAB_REPO" "$LAB_CLONE_DIR" \
    || die "protocol-lab の clone に失敗: $PROTOCOL_LAB_REPO"
fi

LABS_DIR="$LAB_CLONE_DIR/labs"
[ -d "$LABS_DIR" ] || die "labs/ が見つからない: $LABS_DIR"

# --- 2. 未変換Labを1件選ぶ（ファイル名順、README.md は除外）--------------
next_lab=""
while IFS= read -r labpath; do
  labname="$(basename "$labpath")"
  [ "$labname" = "README.md" ] && continue
  if ! lab_is_converted "$labname"; then
    next_lab="$labpath"
    break
  fi
done < <(find "$LABS_DIR" -maxdepth 1 -name '*.md' | sort)

# --- 3. 全部変換済みなら終了 ---------------------------------------------
if [ -z "$next_lab" ]; then
  log "未変換のLabはありません（全Lab変換済み）"
  notify "✅ Protocol Lab: 未変換の記事はありません（全Lab変換済み）"
  exit 0
fi

labname="$(basename "$next_lab")"
slug="$(slug_for_lab "$next_lab")"
log "対象Lab: $labname (slug=$slug)"

# --- 4 & 5. 変換（+ frontmatter不正なら1回リトライ）----------------------
attempt=1
max_attempts=2
converted_ok=0
while [ "$attempt" -le "$max_attempts" ]; do
  log "変換試行 $attempt/$max_attempts"
  if "$SCRIPTS_DIR/convert.sh" "$next_lab" >/dev/null; then
    # convert.sh 内でも検証済みだが、二重に確認しておく。
    if validate_frontmatter "$ARTICLES_DIR/${slug}.md"; then
      converted_ok=1
      break
    fi
    log "frontmatter検証に失敗（試行 $attempt）"
  else
    log "convert.sh が失敗（試行 $attempt）"
  fi
  attempt=$((attempt + 1))
done

if [ "$converted_ok" -ne 1 ]; then
  # 壊れた記事は push しない。生成物があれば消す。
  rm -f "$ARTICLES_DIR/${slug}.md"
  log "変換に失敗（リトライ含む）。pushせず終了。"
  notify "⚠️ Protocol Lab: 変換失敗 ($labname)。記事は作成されませんでした。ログを確認してください。"
  exit 1
fi

article="$ARTICLES_DIR/${slug}.md"
title="$(awk -F'"' '/^title:/{print $2; exit}' "$article")"
[ -n "$title" ] || title="$slug"

# --- 6. converted.json 更新 → commit → push -----------------------------
mark_converted "$labname" "$slug"
log "converted.json を更新: $labname -> $slug"

git -C "$REPO_DIR" add "articles/${slug}.md" "state/converted.json"
if git -C "$REPO_DIR" diff --cached --quiet; then
  log "コミットする変更がありません（既にコミット済み？）"
else
  git -C "$REPO_DIR" commit --quiet -m "articles: add draft ${slug} (${labname})"
  log "コミット作成: ${slug}"
fi

# push は remote があるときだけ。無ければローカルテストとみなしスキップ。
if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
  if git -C "$REPO_DIR" push --quiet origin HEAD; then
    log "push 完了"
  else
    log "push に失敗（後で手動pushが必要）"
    notify "⚠️ Protocol Lab: 下書き $slug を作成しましたが push に失敗しました。手動でpushしてください。"
    exit 1
  fi
else
  log "origin remote が無いため push をスキップ（ローカル実行）"
fi

# --- 7. 下書き作成を通知 -------------------------------------------------
notify "📝 下書き作成: ${title}
Zennダッシュボードで確認 → OKなら:
  ./scripts/publish.sh ${slug}"

log "完了: ${slug}"
