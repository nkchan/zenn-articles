#!/usr/bin/env bash
# daily.sh — 日次の cron エントリポイント（毎日回してよい。公開は2日に1本に自己制限）。
#   1. publish-next.sh <count>  … STUCK(上限で保留された記事)を最優先で再デプロイ→
#      承認キュー→下書きの順に1本だけ公開。前回公開から47h未満なら何もしない。
#   2. status.sh                … 実行後にgit状態とZenn実公開を突合。STUCKが残ればアラート。
#
# ログは logs/daily-YYYYMMDD.log（JST）に追記。cron からは:
#   10 9 * * * cd .../zenn-articles && ./scripts/daily.sh >> logs/cron.log 2>&1
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

# cron は ssh-agent を持たないため、鍵直参照の非対話pushを既定にする。
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new}"

count="${1:-1}"
day="$(TZ=Asia/Tokyo date +%Y%m%d 2>/dev/null || date +%Y%m%d)"
LOG="$LOGS_DIR/daily-$day.log"

{
  log "===== daily.sh 開始 (count=$count) ====="
  # 変換エンジン(Mac mini の claude -p)が push した新しい下書きを取り込む。
  # ff-only で安全に。分岐/衝突していたら publish は行わず中止（壊さない）。
  if git -C "$REPO_DIR" pull --ff-only origin main; then
    "$SCRIPTS_DIR/publish-next.sh" "$count" || log "publish-next.sh 非0終了 ($?)"
    "$SCRIPTS_DIR/status.sh"                 || log "status.sh: STUCK残り(exit1) または API失敗(exit2)"
  else
    log "git pull --ff-only 失敗（分岐/衝突の可能性）。今回は publish を中止。"
    notify "⚠️ Zenn日次: git pull に失敗したため公開を中止しました。手動確認要（cd zenn-articles && git status）。"
  fi
  log "===== daily.sh 終了 ====="
} >>"$LOG" 2>&1
