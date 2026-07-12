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
export CODE_PROMPT_FILE="$PROMPTS_DIR/zenn-convert-in-code.md"
export CODE_CLONE_DIR="$WORK_DIR/protocol-in-code"

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
export PROTOCOL_IN_CODE_REPO="${PROTOCOL_IN_CODE_REPO:-git@github.com:pathvector-studio/protocol-in-code.git}"
export PROTOCOL_IN_CODE_BRANCH="${PROTOCOL_IN_CODE_BRANCH:-main}"

# 変換ソースのリスト。
# 注意: protocol-in-code は有償化予定のため、Zenn（無料公開）には出さない方針。
#   既定から除外している。誤って戻しても publish.sh / publish-next.sh 側で
#   in-code slug のデプロイをハード拒否する（多層防御）。
export SOURCES="${SOURCES:-protocol-lab}"

# protocol-in-code のトラック消化順（COURSE_MAP のコース順）。
# アルファベット順だと教育的順序が壊れるため明示リストで持つ。
export CODE_TRACK_ORDER="${CODE_TRACK_ORDER:-bgp ospf dns tcp tls http-quic parser rpki dhcp rip nat arp qos lb ntp ha icmp dnssec tcp2 stp ice igmp meta}"

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
  # NOTIFY_DISABLE=1 でテスト時に実送信を抑止（.env は NOTIFY_DISABLE を設定しないため
  # コマンドラインの値が生き残る）。
  if [ "${NOTIFY_DISABLE:-0}" = "1" ]; then
    log "[通知抑止] $msg"
    return 0
  fi
  local sent=0
  # if を使い set -e で中断しないようにする（未設定=2 / 失敗=1 は正常系）。
  if _notify_discord  "$msg"; then sent=1; fi
  if _notify_telegram "$msg"; then sent=1; fi
  if [ "$sent" -eq 0 ]; then
    log "WARN: 通知先が未設定/全滅のためスキップ (DISCORD_WEBHOOK_URL / TELEGRAM_*): $msg"
  fi
  return 0
}

# --- Zenn 公開状況（真実）の問い合わせ ------------------------------------
# git の published:true は「Zennに公開を依頼した」に過ぎない。実際に世に出たかの
# 唯一の真実は Zenn の公開API。ここでは you2h（ZENN_USERNAME）の公開記事を引く。
ZENN_API_UA="${ZENN_API_UA:-Mozilla/5.0 (zenn-pipeline health-check)}"

# zenn_live_slugs … 公開中の記事slugを1行1つでstdoutに出す。API失敗時は非0。
zenn_live_slugs() {
  local user="${ZENN_USERNAME:-you2h}" json
  json="$(curl -sS --max-time 25 -H "User-Agent: $ZENN_API_UA" \
    "https://zenn.dev/api/articles?username=${user}&count=500" 2>/dev/null)" || return 1
  [ -n "$json" ] || return 1
  printf '%s' "$json" | jq -e -r '.articles[]?.slug' 2>/dev/null
}

# zenn_is_live <slug> [<live-slugs>] … 公開中なら0。第2引数に取得済み一覧を渡せる。
zenn_is_live() {
  local slug="$1" live="${2:-}"
  [ -n "$live" ] || { live="$(zenn_live_slugs)" || return 2; }
  printf '%s\n' "$live" | grep -qx -- "$slug"
}

# zenn_today_count … 今日(JST)公開された本数をstdoutに出す（数えられなければ ?）。
zenn_today_count() {
  local user="${ZENN_USERNAME:-you2h}" today
  today="$(TZ=Asia/Tokyo date +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"
  curl -sS --max-time 25 -H "User-Agent: $ZENN_API_UA" \
    "https://zenn.dev/api/articles?username=${user}&count=500" 2>/dev/null \
    | jq -r --arg d "$today" '[.articles[]? | select(.published_at[0:10]==$d)] | length' 2>/dev/null \
    || echo '?'
}

# verify_live <slug> [max_wait_sec] [interval_sec]
#   Zennで公開されるまでポーリング。公開されたら0、時間切れなら1。
#   Zennのデプロイは数分の遅延があるため publish 直後の確認に使う。
verify_live() {
  local slug="$1" max="${2:-${VERIFY_MAX_WAIT:-480}}" iv="${3:-${VERIFY_INTERVAL:-30}}"
  local waited=0
  while :; do
    if zenn_is_live "$slug"; then return 0; fi
    [ "$waited" -ge "$max" ] && return 1
    sleep "$iv"; waited=$((waited + iv))
  done
}

# article_published_state <article.md> … frontmatter先頭ブロックの published を出す。
article_published_state() {
  awk 'NR==1&&$0=="---"{fm=1;next} fm&&/^---[[:space:]]*$/{exit} fm&&/^published:/{gsub(/[[:space:]]/,"",$2);print $2;exit}' FS=: "$1"
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

# slug_for_module <module-file.md> <track>
# protocol-in-code の module ファイル名から protocol-in-code-<track>-<NN> を作る。
#   例: module-01-a-segment-carries-state.md + tcp -> protocol-in-code-tcp-01
# Zenn制約（英小文字/数字/ハイフン/アンダースコア、12〜50字）は slug_for_lab と同じ。
slug_for_module() {
  local f track base nn slug
  f="$1"
  track="$2"
  base="$(basename "$f")"
  base="${base%.md}"
  nn="$(printf '%s' "$base" | sed -nE 's/^module-([0-9]+).*/\1/p')"
  [ -z "$nn" ] && nn="$base"
  slug="protocol-in-code-${track}-${nn}"
  slug="$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//')"
  if [ "${#slug}" -gt 50 ]; then
    slug="${slug:0:50}"
    slug="$(printf '%s' "$slug" | sed -E 's/-+$//')"
  fi
  while [ "${#slug}" -lt 12 ]; do slug="${slug}-mod"; done
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
