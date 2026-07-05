#!/usr/bin/env bash
# convert.sh — 単発変換。
#   usage: convert.sh <path-to-lab-md>
# Lab教材Markdownを claude -p でZenn記事に変換し articles/<slug>.md に保存する。
# slug はClaude出力ではなくスクリプト側で固定生成する（冪等性の担保）。
# 成功時は生成した slug を標準出力に1行だけ出す（sync.sh が拾う）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

LAB="${1:-}"
[ -n "$LAB" ]        || die "usage: convert.sh <path-to-lab-md>"
[ -f "$LAB" ]        || die "Labファイルが見つからない: $LAB"
[ -f "$PROMPT_FILE" ] || die "変換プロンプトが見つからない: $PROMPT_FILE"

slug="$(slug_for_lab "$LAB")"
out="$ARTICLES_DIR/${slug}.md"
mkdir -p "$ARTICLES_DIR"

log "変換開始: $(basename "$LAB") -> articles/${slug}.md"

# プロンプト + Lab本文を連結して claude -p に渡す。
input="$(cat "$PROMPT_FILE"; printf '\n\n'; cat "$LAB")"

tmp="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$tmp'" EXIT

# claude -p を暴走防止(--max-turns)・タイムアウト付きで呼ぶ。
# 変換は純粋なテキスト生成なのでツールは不要。失敗は非0で拾う。
set +e
printf '%s' "$input" | timeout "$CLAUDE_TIMEOUT" "$CLAUDE_BIN" -p \
  --max-turns "$CLAUDE_MAX_TURNS" \
  > "$tmp" 2> "$tmp.err"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
  log "claude -p 失敗 (exit $rc)。stderr:"
  sed 's/^/    /' "$tmp.err" >&2 || true
  rm -f "$tmp.err"
  die "変換に失敗した: $(basename "$LAB")"
fi
rm -f "$tmp.err"

# 防御的後処理: 万一Claudeが ```markdown ... ``` でくるんだ場合は剥がす。
# 先頭行が ``` で始まり、かつ2行目以降のどこかに閉じ ``` があるケースのみ対象。
first_line="$(head -n1 "$tmp")"
if printf '%s' "$first_line" | grep -qE '^```'; then
  awk 'NR==1 && /^```/{next} /^```[[:space:]]*$/{stop=1; next} stop==0{print}' "$tmp" > "$tmp.stripped" \
    && mv "$tmp.stripped" "$tmp"
fi

# 先頭・末尾の空行を整える（frontmatterは1行目 --- で始まる必要がある）。
# 先頭の空行だけ落とす。
sed -i '/./,$!d' "$tmp"

if [ ! -s "$tmp" ]; then
  die "変換結果が空だった: $(basename "$LAB")"
fi

mv "$tmp" "$out"
trap - EXIT

log "出力: $out ($(wc -l < "$out") 行)"

# 生成物の frontmatter を検証。壊れていたら非0で返す（呼び出し側がリトライ判断）。
if ! validate_frontmatter "$out"; then
  die "生成記事のfrontmatterが不正: $out"
fi

log "変換成功: slug=$slug"
# slug を stdout に（他のログは stderr ではなく stdout だが、最後の1行がslug）
printf '%s\n' "$slug"
