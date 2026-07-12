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
[ -n "$LAB" ]        || die "usage: convert.sh <path-to-source-md>"
[ -f "$LAB" ]        || die "変換元ファイルが見つからない: $LAB"

# マルチソース対応の上書き（sync.sh が protocol-in-code 用に設定する）:
#   CONVERT_PROMPT_FILE … 使うプロンプト（既定: $PROMPT_FILE = Lab用）
#   CONVERT_SLUG        … 出力slug（既定: slug_for_lab）
#   CONVERT_EXTRA_FILE  … 本文の後ろに引用として連結する参照ファイル（例: 対象の .py）
prompt_file="${CONVERT_PROMPT_FILE:-$PROMPT_FILE}"
[ -f "$prompt_file" ] || die "変換プロンプトが見つからない: $prompt_file"

slug="${CONVERT_SLUG:-$(slug_for_lab "$LAB")}"
out="$ARTICLES_DIR/${slug}.md"
mkdir -p "$ARTICLES_DIR"

log "変換開始: $(basename "$LAB") -> articles/${slug}.md"

# プロンプト + 本文を連結して claude -p に渡す。
input="$(cat "$prompt_file"; printf '\n\n'; cat "$LAB")"
if [ -n "${CONVERT_EXTRA_FILE:-}" ] && [ -f "$CONVERT_EXTRA_FILE" ]; then
  log "参照ソースを連結: $(basename "$CONVERT_EXTRA_FILE")"
  input="$(printf '%s\n\n---\n\n# 参照: 記事が読み解く対象のソースコード（引用の原本として使う）\n\n```python\n' "$input"; cat "$CONVERT_EXTRA_FILE"; printf '\n```\n')"
fi

tmp="$(mktemp)"
tmp_in="$(mktemp)"
printf '%s' "$input" > "$tmp_in"
# shellcheck disable=SC2064
trap "rm -f '$tmp' '$tmp_in'" EXIT

# claude -p を暴走防止(--max-turns)・タイムアウト付きで呼ぶ。
# 変換は純粋なテキスト生成なのでツールは不要。失敗は非0で拾う。
# 移植性: GNU/BSD どちらにも無いことがある `timeout` に依存せず、
# bash のジョブ制御でタイムアウトを実装する（stock macOS には timeout が無い）。
set +e
"$CLAUDE_BIN" -p --max-turns "$CLAUDE_MAX_TURNS" \
  < "$tmp_in" > "$tmp" 2> "$tmp.err" &
claude_pid=$!
( sleep "$CLAUDE_TIMEOUT" && kill -TERM "$claude_pid" 2>/dev/null ) &
watcher_pid=$!
wait "$claude_pid"
rc=$?
kill "$watcher_pid" 2>/dev/null
wait "$watcher_pid" 2>/dev/null
set -e
rm -f "$tmp_in"

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

# 先頭の空行を落とす（frontmatterは1行目 --- で始まる必要がある）。
# 移植性: BSD/macOS の sed -i は GNU と構文が違うため -i を使わずファイル差し替え。
sed '/./,$!d' "$tmp" > "$tmp.trimmed" && mv "$tmp.trimmed" "$tmp"

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
