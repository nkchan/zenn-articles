#!/usr/bin/env bash
# publish-next.sh [count]
# protocol-lab-* の下書き(published:false)を Lab番号(slug末尾のNN)順に、
# 先頭から <count> 本だけ publish.sh で公開する。既定 count=1。
# Zennの1日公開上限に合わせて「1日1〜2本」を回す運用を想定。cronからも呼べる。
#
# 例: ./scripts/publish-next.sh 2   # 次の下書き2本を公開
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

count="${1:-1}"
case "$count" in ''|*[!0-9]*) die "count は整数で指定してください: $count";; esac

# 下書きの protocol-lab-*.md を NN 昇順に集める。
mapfile -t drafts < <(
  for f in "$ARTICLES_DIR"/protocol-lab-*.md; do
    [ -e "$f" ] || continue
    # frontmatter先頭ブロックの published を見る
    st="$(awk 'NR==1&&$0=="---"{fm=1;next} fm&&/^---[[:space:]]*$/{exit} fm&&/^published:/{gsub(/[[:space:]]/,"",$2);print $2;exit}' FS=: "$f")"
    [ "$st" = "false" ] || continue
    slug="$(basename "$f" .md)"
    nn="$(printf '%s' "$slug" | grep -oE '[0-9]+$' || echo 999)"
    printf '%s\t%s\n' "$nn" "$slug"
  done | sort -n | cut -f2
)

if [ "${#drafts[@]}" -eq 0 ]; then
  log "公開待ちの下書きはありません（全て公開済み）"
  notify "✅ Protocol Lab: 公開待ちの下書きはありません"
  exit 0
fi

log "公開待ち: ${#drafts[@]}本。今回は最大 ${count}本を公開します。"
published=0
for slug in "${drafts[@]}"; do
  [ "$published" -ge "$count" ] && break
  log "→ 公開: $slug"
  "$SCRIPTS_DIR/publish.sh" "$slug"
  published=$((published + 1))
done

remaining=$(( ${#drafts[@]} - published ))
log "今回 ${published}本 公開。残り下書き ${remaining}本。"
