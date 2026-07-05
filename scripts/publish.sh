#!/usr/bin/env bash
# publish.sh — 下書きを公開する。
#   usage: publish.sh <slug>
#   1. articles/<slug>.md の published: false を true に書き換え
#   2. commit & push
#   3. 公開URLを Telegram 通知
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

command -v git >/dev/null 2>&1 || die "git が必要です"

slug="${1:-}"
[ -n "$slug" ] || die "usage: publish.sh <slug>"

article="$ARTICLES_DIR/${slug}.md"
[ -f "$article" ] || die "記事が見つからない: $article"

# 現在の published 値を確認。
current="$(awk -F':' '/^published:/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "$article")"
if [ "$current" = "true" ]; then
  log "既に published: true です: $slug"
  notify "ℹ️ ${slug} は既に公開済みです: https://zenn.dev/${ZENN_USERNAME}/articles/${slug}"
  exit 0
fi
if [ "$current" != "false" ]; then
  die "published の値が想定外 ('$current'): $article"
fi

# --- 1. published: false -> true -----------------------------------------
# frontmatter内の published 行のみを対象にする（本文に published: が出ても先頭ブロックのみ）。
tmp="$(mktemp)"
awk '
  BEGIN{fm=0; done=0}
  NR==1 && $0=="---"{fm=1; print; next}
  fm==1 && /^---[[:space:]]*$/{fm=0; print; next}
  fm==1 && done==0 && /^published:[[:space:]]*false[[:space:]]*$/{print "published: true"; done=1; next}
  {print}
' "$article" > "$tmp" && mv "$tmp" "$article"

# 反映確認
new="$(awk -F':' '/^published:/{gsub(/[[:space:]]/,"",$2); print $2; exit}' "$article")"
[ "$new" = "true" ] || die "published の書き換えに失敗: $article"
log "published: true に更新: $slug"

# --- 2. commit & push ----------------------------------------------------
git -C "$REPO_DIR" add "articles/${slug}.md"
if git -C "$REPO_DIR" diff --cached --quiet; then
  log "コミットする変更がありません"
else
  git -C "$REPO_DIR" commit --quiet -m "articles: publish ${slug}"
  log "コミット作成: publish ${slug}"
fi

if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
  git -C "$REPO_DIR" push --quiet origin HEAD || die "push に失敗: $slug"
  log "push 完了"
else
  log "origin remote が無いため push をスキップ（ローカル実行）"
fi

# --- 3. 公開通知 ---------------------------------------------------------
url="https://zenn.dev/${ZENN_USERNAME}/articles/${slug}"
notify "🚀 公開しました: ${url}"
log "公開完了: ${url}"
