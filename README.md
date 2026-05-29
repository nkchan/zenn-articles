# zenn-articles

Kaoru の Zenn 投稿用リポジトリ。Zenn CLI が `articles/` と `books/` を読み取って同期する。

## 構成

- `articles/` — 個別記事 (`YYYYMMDD-<slug>.md`)
- `books/` — 連載・本形式 (現状未使用)

## 投稿ワークフロー

1. ドラフトは OpenClaw の `article-draft` skill (毎晩 23:00 cron) で生成 → `articles/` に追加
2. 公開判定は手動。frontmatter の `published: true` で公開
3. テーマは Protocol Lab / BGP Sentinel / OpenClaw 運用 / AI agent 設計を中心に

## 関連

- 司令室: [`nkchan-company/COMMAND_CENTER.md`](../COMMAND_CENTER.md)
- 記事生成skill: `~/.openclaw/workspace/skills/article-draft/SKILL.md`
- 公開skill: `~/.openclaw/workspace/skills/publish-article/SKILL.md`
