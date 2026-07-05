#!/usr/bin/env bash
# common.sh — 全スクリプトが source する共通処理。
# ここでは set -e しない（source元が制御する）。パスやenv、通知、slug生成、frontmatter検証をまとめる。

# --- PATH の明示 ---------------------------------------------------------
# cron 実行時は最小PATHになるため、claude / npx / git が確実に見つかるように前置する。
# Mac(Homebrew), Linux, native installer の代表的な場所を並べる。
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.config/Claude/claude-code:$PATH"

# --- ディレクトリ解決 ----------------------------------------------------
# common.sh の1つ上（scripts/ の親）がリポジトリルート。
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR="${ZENN_CONTENT_DIR:-$(cd "$COMMON_DIR/.." && pwd)}"
export SCRIPTS_DIR="$REPO_DIR/scripts"
export ARTICLES_DIR="$REPO_DIR/articles"
export PROMPTS_DIR="$REPO_DIR/prompts"
export STATE_DIR="$REPO_DIR/state"
export WORK_DIR="$REPO_DIR/work"
export LOGS_DIR="$REPO_DIR/logs"
export CONVERTED_JSON="$STATE_DIR/converted.json"
export PROMPT_FILE="$PROMPTS_DIR/zenn-convert.md"
export LAB_CLONE_DIR="$WORK_DIR/protocol-lab"

# --- .env 読み込み -------------------------------------------------------
if [ -f "$REPO_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$REPO_DIR/.env"
  set +a
fi

# --- 既定値 --------------------------------------------------------------
export CLAUDE_BIN="${CLAUDE_BIN:-claude}"
export CLAUDE_TIMEOUT="${CLAUDE_TIMEOUT:-600}"
export CLAUDE_MAX_TURNS="${CLAUDE_MAX_TURNS:-1}"
export ZENN_USERNAME="${ZENN_USERNAME:-nkchan}"
export PROTOCOL_LAB_REPO="${PROTOCOL_LAB_REPO:-git@github.com:pathvector-studio/protocol-lab.git}"
export PROTOCOL_LAB_BRANCH="${PROTOCOL_LAB_BRANCH:-main}"

# --- ログ ----------------------------------------------------------------
# ログは stderr に出す。stdout は convert.sh の slug 出力など「値」専用に空けておく。
log()  { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

# --- 通知 ----------------------------------------------------------------
# notify <message>
#   設定済みのチャンネル（Discord / Telegram）すべてに送る。
#   どのチャンネルも未設定なら警告して続行（通知失敗でパイプラインは止めない）。

# Discordへ送る。DISCORD_WEBHOOK_URL 未設定なら 2（=未設定）を返す。
_notify_discord() {
  local msg="$1"
  [ -n "${DISCORD_WEBHOOK_URL:-}" ] || return 2
  local payload http_code
  # JSONはjqで安全に組み立てる（改行・引用符・絵文字をエスケープ）。
  payload="$(jq -n --arg c "$msg" '{content: $c}')"
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    --max-time 20 \
    -H 'Content-Type: application/json' \
    -X POST "$DISCORD_WEBHOOK_URL" \
    -d "$payload" 2>/dev/null || echo "000")"
  # Discord webhook は成功時 204 (?wait=true なら 200)。
  case "$http_code" in
    200|204) log "Discord通知OK"; return 0 ;;
    *)       log "WARN: Discord通知に失敗 (HTTP $http_code)"; return 1 ;;
  esac
}

# Telegramへ送る。token/chat_id 未設定なら 2（=未設定）を返す。
_notify_telegram() {
  local msg="$1"
  { [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; } || return 2
  # 既定は本番のTelegram API。テスト時はローカルmockに差し替え可能。
  local api_base="${TELEGRAM_API_BASE:-https://api.telegram.org}"
  local http_code
  http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
    --max-time 20 \
    -X POST "${api_base}/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${msg}" \
    --data-urlencode "disable_web_page_preview=true" 2>/dev/null || echo "000")"
  if [ "$http_code" != "200" ]; then
    log "WARN: Telegram通知に失敗 (HTTP $http_code)"
    return 1
  fi
  log "Telegram通知OK"
  return 0
}

notify() {
  local msg="$1"
  local sent=0
  # if を使い set -e で中断しないようにする（未設定=2 / 失敗=1 は正常系）。
  if _notify_discord  "$msg"; then sent=1; fi
  if _notify_telegram "$msg"; then sent=1; fi
  if [ "$sent" -eq 0 ]; then
    log "WARN: 通知先が未設定/全滅のためスキップ (DISCORD_WEBHOOK_URL / TELEGRAM_*): $msg"
  fi
  return 0
}

# --- slug 生成 -----------------------------------------------------------
# slug_for_lab <lab-file.md>
# Labファイル名の先頭 <proto>-<NN> を取り出し protocol-lab-<proto>-<NN> にする。
#   例: bgp-01-as-prefix-announcement.md -> protocol-lab-bgp-01
# Zenn制約: 半角英小文字・数字・ハイフン・アンダースコアのみ、12〜50字。
slug_for_lab() {
  local f base key slug
  f="$1"
  base="$(basename "$f")"
  base="${base%.md}"
  key="$(printf '%s' "$base" | grep -oE '^[a-z0-9]+-[0-9]+' || true)"
  [ -z "$key" ] && key="$base"
  slug="protocol-lab-${key}"
  # 許可文字以外をハイフンに寄せ、連続ハイフンを畳み、前後ハイフンを除去。
  slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//')"
  # 50字上限（超えたら切り、末尾ハイフンを除去）。
  if [ "${#slug}" -gt 50 ]; then
    slug="${slug:0:50}"
    slug="$(printf '%s' "$slug" | sed -E 's/-+$//')"
  fi
  # 12字下限（万一短ければパディング）。実運用のLab名では発生しない。
  while [ "${#slug}" -lt 12 ]; do slug="${slug}-lab"; done
  printf '%s' "$slug"
}

# --- frontmatter 検証 ----------------------------------------------------
# validate_frontmatter <article.md>
# 先頭が --- で始まり、必須キー title/emoji/type/topics/published が
# frontmatterブロック内に存在すれば 0、なければ 1。
validate_frontmatter() {
  local file="$1"
  [ -f "$file" ] || { log "検証失敗: ファイルが無い: $file"; return 1; }
  # 先頭行が --- か
  if [ "$(head -n1 "$file")" != "---" ]; then
    log "検証失敗: 先頭が '---' で始まっていない: $file"
    return 1
  fi
  # frontmatterブロック（1行目の --- の次から、次の --- まで）を抜き出す
  local fm
  fm="$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$file")"
  local key missing=0
  for key in title emoji type topics published; do
    if ! printf '%s\n' "$fm" | grep -qE "^${key}:"; then
      log "検証失敗: frontmatterに '${key}:' が無い: $file"
      missing=1
    fi
  done
  return "$missing"
}

# --- converted.json ヘルパ ----------------------------------------------
# lab_is_converted <lab-file.md-basename>  … 既に変換済みなら 0
lab_is_converted() {
  local labname="$1"
  [ -f "$CONVERTED_JSON" ] || return 1
  jq -e --arg k "$labname" 'has($k)' "$CONVERTED_JSON" >/dev/null 2>&1
}

# mark_converted <lab-file.md-basename> <slug>  … converted.json に追記（原子的に）
mark_converted() {
  local labname="$1" slug="$2" tmp
  [ -f "$CONVERTED_JSON" ] || echo '{}' > "$CONVERTED_JSON"
  tmp="$(mktemp)"
  jq --arg k "$labname" --arg v "$slug" '. + {($k): $v}' "$CONVERTED_JSON" > "$tmp" \
    && mv "$tmp" "$CONVERTED_JSON"
}
