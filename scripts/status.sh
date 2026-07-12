#!/usr/bin/env bash
# status.sh — git上の published 状態と Zenn の実公開状況を突合し、ズレを検出する。
#
# 背景: publish.sh は articles/*.md を published:true にして push するだけで、
#   Zennが実際に公開したかは見ていなかった。Zennには投稿数上限があり、超過分は
#   「デプロイされませんでした」と黙って保留される（例: 2026-07 の tls-09 / roadmap）。
#   その結果 git上は公開済みなのにURLが見られない“帳尻ズレ”が発生する。
#   このスクリプトが両者を突き合わせ、STUCK（公開依頼済みだが未公開）を洗い出す。
#
# 使い方:
#   ./scripts/status.sh          # 突合レポートを表示。STUCKがあれば通知し exit 1。
#   ./scripts/status.sh --quiet  # 問題が無ければ通知しない（cron日次監視向け・既定）
#   STATUS_NOTIFY_OK=1 で正常時も通知する。
#
# 終了コード: 0=ズレ無し / 1=STUCKあり / 2=Zenn API取得失敗
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

live="$(zenn_live_slugs)" || { notify "❌ Zenn突合: 公開API取得に失敗（ネットワーク/jq）"; exit 2; }

ok=(); stuck=(); drafts=(); ghost=(); incode_leak=()
for f in "$ARTICLES_DIR"/*.md; do
  [ -e "$f" ] || continue
  slug="$(basename "$f" .md)"
  pub="$(article_published_state "$f")"
  is_live=1; printf '%s\n' "$live" | grep -qx -- "$slug" && is_live=0
  # protocol-in-code は有償化予定でZenn非公開ポリシー。published:true か公開中なら漏れ。
  case "$slug" in
    protocol-in-code-*)
      { [ "$pub" = "true" ] || [ "$is_live" -eq 0 ]; } && incode_leak+=("$slug")
      ;;
  esac
  if   [ "$pub" = "true"  ] && [ "$is_live" -eq 0 ]; then ok+=("$slug")
  elif [ "$pub" = "true"  ] && [ "$is_live" -ne 0 ]; then stuck+=("$slug")
  elif [ "$pub" = "false" ] && [ "$is_live" -eq 0 ]; then ghost+=("$slug")
  else drafts+=("$slug"); fi
done

today="$(zenn_today_count || echo '?')"
log "=== Zenn 公開突合 (user=${ZENN_USERNAME}) ==="
log "公開OK ${#ok[@]} / STUCK(未公開) ${#stuck[@]} / 下書き ${#drafts[@]} / 異常(false but live) ${#ghost[@]} / in-code漏れ ${#incode_leak[@]}"
log "本日(JST)公開済: ${today}本"
[ "${#stuck[@]}" -gt 0 ] && log "STUCK: ${stuck[*]}"
[ "${#ghost[@]}" -gt 0 ] && log "GHOST(published:falseなのに公開中): ${ghost[*]}"

rc=0
if [ "${#incode_leak[@]}" -gt 0 ]; then
  notify "⛔ Zenn突合: 有償化予定の protocol-in-code がZennに出ています → ${incode_leak[*]}（published:false化＋非公開ポリシー要確認！）"
  rc=1
fi
if [ "${#stuck[@]}" -gt 0 ]; then
  notify "⚠️ Zenn突合: published:true だが未公開が ${#stuck[@]}本 → ${stuck[*]}（投稿上限で保留の可能性。publish-next.sh が翌日以降に自動再デプロイ）"
  rc=1
fi
if [ "${#ghost[@]}" -gt 0 ]; then
  notify "⚠️ Zenn突合: published:false なのにZennで公開中: ${ghost[*]}（要確認）"
  rc=1
fi
if [ "$rc" -eq 0 ]; then
  log "突合OK: ズレなし"
  [ "${STATUS_NOTIFY_OK:-0}" = "1" ] && notify "✅ Zenn突合OK: 公開${#ok[@]} / 下書き${#drafts[@]} / 本日${today}本"
fi
exit "$rc"
