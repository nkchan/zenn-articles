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
- `scripts/publish-next.sh` — 公開待ちを**1本だけ**公開する（N を渡しても 1 に丸める）。順番は STUCK（上限で保留された記事）→ `state/publish-queue.txt` → protocol-lab の下書き。
- `scripts/daily.sh` — 毎日の cron 用。`publish-next.sh` と `status.sh` を回す。
- `state/publish-queue.txt` — Kaoru が公開を OK した記事の順番待ち（1行1 slug）。記事は `published: false` のまま `articles/` に置いておく。

### 公開ペースのルール（Zenn の投稿数上限対策）

詳細は `pathvector-studio/ops` の `docs/zenn.md`。

- 新規公開は1回に1本。前回の新規公開から `MIN_PUBLISH_INTERVAL_HOURS`（既定47h）経つまで、`publish.sh` も `publish-next.sh` も公開しない。毎日同じ時刻の cron なら2日に1本になる
- 前回の公開時刻は Zenn の公開 API と git の `articles: publish` コミットの新しい方で判定する（API が落ちていても守れるように）
- どうしても今すぐ出すときだけ `FORCE_PUBLISH=1 ./scripts/publish.sh <slug>`
- 本（`books/`）はスクリプトでは公開しない。副業許可が出るまで有料本は出さない
- `prompts/zenn-convert.md` — Protocol Lab教材 → Zenn記事の変換プロンプト。
- `prompts/zenn-article.md` — 任意プロジェクト/やったこと → Zenn記事の汎用執筆プロンプト（他の題材をこの運用に合流させる用）。
- `state/converted.json` — 変換済み管理（冪等性の唯一の真実）。
- 通知は Discord webhook / Telegram bot（`.env`、両対応・片方でも可）。

セットアップ: `cp .env.example .env` して埋める（`DISCORD_WEBHOOK_URL` 等）。
Zenn の GitHub 連携はこのリポジトリで設定済み。cron 例:

```
0 9 * * 1 cd /path/to/zenn-articles && ./scripts/sync.sh >> logs/sync.log 2>&1
10 9 * * * cd /path/to/zenn-articles && ./scripts/daily.sh >> logs/cron.log 2>&1
```

> 既存の手書き記事 `articles/20260512-bgp-lab-01-one-prefix.md`（BGP Lab 01）は
> `state/converted.json` に登録済みで、パイプラインは重複変換しない。

## 関連

- 司令室: [`nkchan-company/COMMAND_CENTER.md`](../COMMAND_CENTER.md)
- 記事生成skill: `~/.openclaw/workspace/skills/article-draft/SKILL.md`
- 公開skill: `~/.openclaw/workspace/skills/publish-article/SKILL.md`
