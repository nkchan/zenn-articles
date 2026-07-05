# zenn-articles

Kaoru の Zenn 投稿用リポジトリ。Zenn CLI が `articles/` と `books/` を読み取って同期する。

## 構成

- `articles/` — 個別記事 (`YYYYMMDD-<slug>.md`)
- `books/` — 連載・本形式 (現状未使用)

## 投稿ワークフロー

1. ドラフトは OpenClaw の `article-draft` skill (毎晩 23:00 cron) で生成 → `articles/` に追加
2. 公開判定は手動。frontmatter の `published: true` で公開
3. テーマは Protocol Lab / BGP Sentinel / OpenClaw 運用 / AI agent 設計を中心に

## Protocol Lab 自動変換パイプライン (`scripts/`)

`pathvector-studio/protocol-lab` の Lab 教材を `claude -p` で日本語 Zenn 記事に変換し、
このリポジトリ経由で Zenn に公開するパイプライン。運用機は M4 Mac mini（週1 cron）。

```
[cron 週1] scripts/sync.sh
  1. protocol-lab を pull → 未変換Labを1件選ぶ (state/converted.json と照合)
  2. claude -p で変換 → articles/<slug>.md (published: false)
  3. commit & push（Zenn上では下書き）→ Discord/Telegram 通知
[人間] Zennダッシュボードで確認 → scripts/publish.sh <slug> で公開
```

- `scripts/convert.sh <lab.md>` — 単発変換。slug は `protocol-lab-<proto>-<NN>` で固定生成。
- `scripts/sync.sh` — 未変換Labを1件だけ変換して push。1実行1記事。
- `scripts/publish.sh <slug>` — `published: false → true` にして公開。
- `scripts/publish-next.sh [N]` — 下書きを Lab番号順に N 本だけ公開（既定1）。Zennの1日公開上限に合わせて日々回す用。
- `prompts/zenn-convert.md` — 変換プロンプト。
- `state/converted.json` — 変換済み管理（冪等性の唯一の真実）。
- 通知は Discord webhook / Telegram bot（`.env`、両対応・片方でも可）。

セットアップ: `cp .env.example .env` して埋める（`DISCORD_WEBHOOK_URL` 等）。
Zenn の GitHub 連携はこのリポジトリで設定済み。cron 例:

```
0 9 * * 1 cd /path/to/zenn-articles && ./scripts/sync.sh >> logs/sync.log 2>&1
```

> 既存の手書き記事 `articles/20260512-bgp-lab-01-one-prefix.md`（BGP Lab 01）は
> `state/converted.json` に登録済みで、パイプラインは重複変換しない。

## 関連

- 司令室: [`nkchan-company/COMMAND_CENTER.md`](../COMMAND_CENTER.md)
- 記事生成skill: `~/.openclaw/workspace/skills/article-draft/SKILL.md`
- 公開skill: `~/.openclaw/workspace/skills/publish-article/SKILL.md`
