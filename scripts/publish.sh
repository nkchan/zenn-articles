#!/usr/bin/env bash
# publish.sh — 下書きを公開し、Zennで実際に公開されたことまで確認する。
#   usage: publish.sh <slug> [--redeploy]
#   1. articles/<slug>.md の published: false を true に書き換え
#      （--redeploy 指定時は既に true の記事を、末尾改行トグルで再デプロイ）
#   2. commit & push
#   3. Zennの公開APIをポーリングし、実際に公開されたか確認してから通知
#
# 終了コード: 0=公開確認OK / 3=push済みだがZen未公開（投稿上限で保留の可能性）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

command -v git >/dev/null 2>&1 || die "git が必要です"

slug="${1:-}"
[ -n "$slug" ] || die "usage: publish.sh <slug> [--redeploy]"
redeploy=0
[ "${2:-}" = "--redeploy" ] && redeploy=1

# --- デプロイ禁止ポリシー: protocol-in-code は有償化予定のためZenn公開禁止 ------
# 生成停止（SOURCES）に加え、公開の最終choke pointでもハード拒否する（多層防御）。
case "$slug" in
  protocol-in-code-*)
    die "protocol-in-code は有償化予定のためZenn公開禁止（デプロイ抑止ポリシー）: $slug" ;;
esac

article="$ARTICLES_DIR/${slug}.md"
[ -f "$article" ] || die "記事が見つからない: $article"

# 現在の published 値を確認。
current="$(article_published_state "$article")"
if [ "$current" = "true" ]; then
  if [ "$redeploy" -eq 1 ]; then
    log "再デプロイ: $slug（既に published:true。Zennの前回デプロイが保留された記事を再送）"
  else
    log "既に published: true です: $slug"
    notify "ℹ️ ${slug} は既に公開済みです: https://zenn.dev/${ZENN_USERNAME}/articles/${slug}"
    exit 0
  fi
elif [ "$current" = "false" ]; then
  # --- 1. published: false -> true ---------------------------------------
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
  new="$(article_published_state "$article")"
  [ "$new" = "true" ] || die "published の書き換えに失敗: $article"
  log "published: true に更新: $slug"
else
  die "published の値が想定外 ('$current'): $article"
fi

# 再デプロイで frontmatter に差分が無い場合、ZennのGitHub連携は「変更された記事だけ」を
# 再処理するため、無変更のpushでは何も起きない（過去に空コミットで再デプロイに失敗した）。
# 末尾改行をトグルして必ず1バイトの実差分を作り、確実にデプロイをトリガする（本文は不変）。
if git -C "$REPO_DIR" diff --quiet -- "articles/${slug}.md" \
   && git -C "$REPO_DIR" diff --cached --quiet -- "articles/${slug}.md"; then
  if [ -n "$(tail -c1 "$article")" ]; then
    printf '\n' >> "$article"                       # 末尾に改行が無い→足す
  else
    tmp="$(mktemp)"; printf '%s' "$(cat "$article")" > "$tmp"; mv "$tmp" "$article"  # 末尾改行を除く
  fi
  log "再デプロイ用に末尾改行をトグル（本文は不変）: $slug"
fi

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

# --- 3. Zennで実際に公開されたか確認してから通知 -------------------------
# push しただけでは「公開したつもり」で終わる。Zennは投稿数上限を超えると
# 「デプロイされませんでした」と黙って保留するため、公開APIで生存確認する。
url="https://zenn.dev/${ZENN_USERNAME}/articles/${slug}"
log "Zennのデプロイを確認中（最大 ${VERIFY_MAX_WAIT:-480}s）… $slug"
if verify_live "$slug"; then
  notify "🚀 公開しました: ${url}"
  log "公開確認OK: ${url}"
else
  notify "⏳ ${slug} を push しましたが Zenn でまだ公開されていません（投稿数上限で保留の可能性: https://zenn.dev/faq/rate-limit ）。status.sh で追跡し、翌日以降に自動再デプロイします。"
  log "WARN: push済みだがZen未公開（上限の可能性）: ${slug}"
  exit 3   # 呼び出し側（publish-next.sh）はこの日はここで打ち切る
fi

# --- 4. SNS告知（任意・ベストエフォート） ----------------------------------
# .env で SOCIAL_ANNOUNCE_CMD に pipeline/social/announce.sh を指定すると
# 公開のたびに Bluesky へ日本語ポストする。X は announce.sh の担当ではなく
# IFTTT の RSS アプレット（Zenn フィード監視）が独立に投稿する。
# 失敗しても公開処理は成功扱い。
# 公開が確認できた記事のみ告知する（保留中は exit 3 済みでここには来ない）。
if [ -n "${SOCIAL_ANNOUNCE_CMD:-}" ] && [ -x "$SOCIAL_ANNOUNCE_CMD" ]; then
  ja_title="$(awk -F'"' '/^title:/{print $2; exit}' "$article")"
  "$SOCIAL_ANNOUNCE_CMD" --slug "$slug" --url "$url" --title "${ja_title:-$slug}" --lang ja \
    || log "SNS告知に失敗（公開自体は完了）"
fi
