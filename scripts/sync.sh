#!/usr/bin/env bash
# sync.sh — メインパイプライン（cron 週1〜日次想定）。
# SOURCES（既定: protocol-lab protocol-in-code）を順に処理し、各ソースにつき
# 未変換の先頭1件を Zenn 下書きへ変換する（1実行 = ソースごとに最大1記事）。
#
# protocol-lab      : labs/*.md をファイル名順。converted.json キーは lab の basename（従来通り）。
# protocol-in-code  : modules/<track>/module-*.md を CODE_TRACK_ORDER のトラック順 → NN順。
#                     converted.json キーは "<track>/<basename>"（トラック間の重複回避）。
#                     module 文書が参照する src/**.py を見つけて変換入力に連結する。
#
# 各件: 変換 → frontmatter検証（1回リトライ）→ converted.json 更新 → commit → push → 通知。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

command -v jq  >/dev/null 2>&1 || die "jq が必要です"
command -v git >/dev/null 2>&1 || die "git が必要です"

# --- 共通: clone or pull ---------------------------------------------------
# ensure_clone <repo-url> <branch> <dir> <label>
ensure_clone() {
  local repo="$1" branch="$2" dir="$3" label="$4"
  mkdir -p "$WORK_DIR"
  if [ -d "$dir/.git" ]; then
    log "$label を pull: $dir"
    git -C "$dir" fetch --quiet origin "$branch"
    git -C "$dir" checkout --quiet "$branch"
    git -C "$dir" reset --hard --quiet "origin/$branch"
  else
    log "$label を clone: $repo -> $dir"
    git clone --quiet --branch "$branch" "$repo" "$dir" \
      || die "$label の clone に失敗: $repo"
  fi
}

# --- 共通: 1件変換 → 検証 → commit/push → 通知 ------------------------------
# convert_and_ship <source-md> <slug> <state-key> <label> [extra-file]
#   0: 成功 / 1: 失敗（通知済み）
convert_and_ship() {
  local src="$1" slug="$2" key="$3" label="$4" extra="${5:-}"
  local attempt=1 max_attempts=2 converted_ok=0

  while [ "$attempt" -le "$max_attempts" ]; do
    log "変換試行 $attempt/$max_attempts ($key)"
    if CONVERT_SLUG="$slug" CONVERT_EXTRA_FILE="$extra" \
       CONVERT_PROMPT_FILE="${CONVERT_PROMPT_OVERRIDE:-$PROMPT_FILE}" \
       "$SCRIPTS_DIR/convert.sh" "$src" >/dev/null; then
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
    rm -f "$ARTICLES_DIR/${slug}.md"
    log "変換に失敗（リトライ含む）。pushせず終了。"
    notify "⚠️ ${label}: 変換失敗 (${key})。記事は作成されませんでした。ログを確認してください。"
    return 1
  fi

  local article title
  article="$ARTICLES_DIR/${slug}.md"
  title="$(awk -F'"' '/^title:/{print $2; exit}' "$article")"
  [ -n "$title" ] || title="$slug"

  mark_converted "$key" "$slug"
  log "converted.json を更新: $key -> $slug"

  git -C "$REPO_DIR" add "articles/${slug}.md" "state/converted.json"
  if git -C "$REPO_DIR" diff --cached --quiet; then
    log "コミットする変更がありません（既にコミット済み？）"
  else
    git -C "$REPO_DIR" commit --quiet -m "articles: add draft ${slug} (${key})"
    log "コミット作成: ${slug}"
  fi

  if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
    if git -C "$REPO_DIR" push --quiet origin HEAD; then
      log "push 完了"
    else
      log "push に失敗（後で手動pushが必要）"
      notify "⚠️ ${label}: 下書き $slug を作成しましたが push に失敗しました。手動でpushしてください。"
      return 1
    fi
  else
    log "origin remote が無いため push をスキップ（ローカル実行）"
  fi

  notify "📝 下書き作成: ${title}
Zennダッシュボードで確認 → OKなら:
  ./scripts/publish.sh ${slug}"
  log "完了: ${slug}"
  return 0
}

# --- source: protocol-lab ----------------------------------------------------
sync_protocol_lab() {
  ensure_clone "$PROTOCOL_LAB_REPO" "$PROTOCOL_LAB_BRANCH" "$LAB_CLONE_DIR" "protocol-lab"
  local labs_dir="$LAB_CLONE_DIR/labs"
  [ -d "$labs_dir" ] || die "labs/ が見つからない: $labs_dir"

  local next_lab="" labpath labname
  while IFS= read -r labpath; do
    labname="$(basename "$labpath")"
    [ "$labname" = "README.md" ] && continue
    if ! lab_is_converted "$labname"; then
      next_lab="$labpath"
      break
    fi
  done < <(find "$labs_dir" -maxdepth 1 -name '*.md' | sort)

  if [ -z "$next_lab" ]; then
    log "protocol-lab: 未変換のLabはありません（全Lab変換済み）"
    notify "✅ Protocol Lab: 未変換の記事はありません（全Lab変換済み）"
    return 0
  fi

  labname="$(basename "$next_lab")"
  local slug
  slug="$(slug_for_lab "$next_lab")"
  log "対象Lab: $labname (slug=$slug)"
  CONVERT_PROMPT_OVERRIDE="$PROMPT_FILE" \
    convert_and_ship "$next_lab" "$slug" "$labname" "Protocol Lab"
}

# --- source: protocol-in-code -------------------------------------------------
sync_protocol_in_code() {
  ensure_clone "$PROTOCOL_IN_CODE_REPO" "$PROTOCOL_IN_CODE_BRANCH" "$CODE_CLONE_DIR" "protocol-in-code"
  local modules_dir="$CODE_CLONE_DIR/modules"
  [ -d "$modules_dir" ] || die "modules/ が見つからない: $modules_dir"
  [ -f "$CODE_PROMPT_FILE" ] || die "in-code 用プロンプトが見つからない: $CODE_PROMPT_FILE"

  # トラック順（CODE_TRACK_ORDER）→ module NN 順で未変換の先頭1件を選ぶ。
  local next_module="" next_track="" track modpath modname key
  for track in $CODE_TRACK_ORDER; do
    [ -d "$modules_dir/$track" ] || continue
    while IFS= read -r modpath; do
      modname="$(basename "$modpath")"
      key="${track}/${modname}"
      if ! lab_is_converted "$key"; then
        next_module="$modpath"
        next_track="$track"
        break 2
      fi
    done < <(find "$modules_dir/$track" -maxdepth 1 -name 'module-*.md' | sort)
  done

  if [ -z "$next_module" ]; then
    log "protocol-in-code: 未変換のmoduleはありません（全module変換済み）"
    notify "✅ Protocol in Code: 未変換の記事はありません（全module変換済み）"
    return 0
  fi

  modname="$(basename "$next_module")"
  key="${next_track}/${modname}"
  local slug
  slug="$(slug_for_module "$next_module" "$next_track")"
  log "対象module: $key (slug=$slug)"

  # module 文書の Position が指す src/**.py を変換入力に連結する（コード引用の原本）。
  local srcrel="" extra=""
  srcrel="$(grep -m1 -oE 'src/protocol_in_code/[A-Za-z0-9_/.-]+\.py' "$next_module" || true)"
  if [ -n "$srcrel" ] && [ -f "$CODE_CLONE_DIR/$srcrel" ]; then
    extra="$CODE_CLONE_DIR/$srcrel"
  else
    log "WARN: 参照ソースが見つからない（本文のみで変換）: ${srcrel:-<not-found>}"
  fi

  CONVERT_PROMPT_OVERRIDE="$CODE_PROMPT_FILE" \
    convert_and_ship "$next_module" "$slug" "$key" "Protocol in Code" "$extra"
}

# --- main: SOURCES を順に処理 ---------------------------------------------------
overall_rc=0
for source in $SOURCES; do
  case "$source" in
    protocol-lab)     sync_protocol_lab     || overall_rc=1 ;;
    protocol-in-code) sync_protocol_in_code || overall_rc=1 ;;
    *) log "WARN: 未知のソースをスキップ: $source" ;;
  esac
done
exit "$overall_rc"
