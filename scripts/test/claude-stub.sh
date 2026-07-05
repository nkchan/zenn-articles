#!/usr/bin/env bash
# claude-stub.sh — テスト用の "claude -p" 代替。
# 本物の claude と同じインターフェース（stdinにプロンプト+Lab、stdoutに記事）を模倣する。
# 認証不要でパイプラインのプラミング（引数解釈・slug生成・記事配置・frontmatter検証・
# converted.json の冪等更新）を検証するために使う。実運用では本物の claude が担う。
#
# 挙動:
#   - stdin に bgp-01 のLab（"One Prefix Announcement"）が含まれていれば、
#     事前に用意した実変換済みfixtureをそのまま出力する。
#   - それ以外のLabには、frontmatterが妥当な汎用記事を生成して出力する
#     （冪等性テスト等、記事本文の中身が問われない検証用）。
set -euo pipefail

STUB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$STUB_DIR/fixtures/bgp-01.expected.md"

input="$(cat)"

if printf '%s' "$input" | grep -q "One Prefix Announcement"; then
  cat "$FIXTURE"
  exit 0
fi

# --- 汎用フォールバック ---------------------------------------------------
# 入力は「プロンプト + Lab本文」。プロンプトにも H1 があるため、最後の H1
# (= Lab本文のタイトル。Labは先頭に単一の "# ..." を持つ) をタイトル種にする。
h1="$(printf '%s\n' "$input" | grep -E '^# ' | tail -1 | sed -E 's/^#[[:space:]]*//' || true)"
[ -n "$h1" ] || h1="Protocol Lab 教材"

cat <<EOF
---
title: "${h1}（Protocol Lab）"
emoji: "🌐"
type: "tech"
topics: ["network", "protocol", "containerlab"]
published: false
---

この記事は、ネットワークプロトコルを手を動かして学ぶフリー教材シリーズ **Protocol Lab** の一部です。

- リポジトリ: https://github.com/pathvector-studio/protocol-lab

（これはテスト用スタブが生成したプレースホルダ本文です。実運用では claude -p が
Lab教材を日本語のZenn記事に変換します。）

:::message
このLabは閉じた検証環境で実行してください。
:::

---

**Protocol Lab について**

シリーズ一覧: https://github.com/pathvector-studio/protocol-lab

役に立ったら ⭐️ をお願いします。次回もお楽しみに。
EOF
