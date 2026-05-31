---
title: "Linuxカーネルが「AI生成パッチ」の規制強化へ。Linus激怒の背景と『Assisted-by:』タグ導入の意図"
emoji: "🤖"
type: "tech"
topics:
  - "ai"
  - "linux"
  - "github"
  - "oss"
  - "security"
published: true
---

## TL;DR

- AIツールが生成した低品質・重複のパッチ（AI Slop）がLinuxカーネルのメーリングリストに溢れ、メンテナーの負担が限界に達している。
- Linus Torvalds氏がこれに激怒し、AIが発見したバグを非公開で報告する行為を禁止。公開メーリングリストでの報告を義務付ける方針を打ち出した。
- AIの支援を受けたパッチへの「`Assisted-by:`」タグの付与が義務化された。`Signed-off-by` は人間の責任範囲として厳密に区別される。
- OSS開発において、AIエージェントの自律化が進む中で「品質担保」と「人間の説明責任」を明確にするモデルケースとして注目される。

## 背景：カーネル開発現場を襲う「AI Slop（ノイズ）」

2026年に入り、自律型AIエージェントや高度なLLMによる静的解析技術は飛躍的な進化を遂げ、一部では古いコードに潜んでいた脆弱性（例：CVE-2026-31431）を発見するなどの成果を上げています。

一方で、カーネル開発の現場であるLinux Kernel Mailing List（LKML）では深刻な問題が浮上しました。それは、**「AIによる低品質で無意味なバグ報告・些細なリファクタリング提案（AI Slop）」の氾濫**です。

AIツールは既存の静的解析ツールよりも容易に"もっともらしい"レポートやパッチを生成できます。しかし、カーネル全体の文脈やアーキテクチャの意図を無視した表面的な修正が大量に送りつけられる事態となりました。

### AI Slopの具体例：文脈を無視した最適化提案

例えば、AIが以下のような「無意味なパッチ」を自動生成してMLに送信してしまうケースが頻発しています。

```c
// 元のコード：意図的なディレイや特定アーキテクチャ向けのワークアラウンドが含まれている
void legacy_device_init() {
    setup_registers();
    mdelay(10); /* Hardware requires a 10ms settling time */
    enable_interrupts();
}
```

AIエージェントは、これを単なる「非効率な待機処理」と誤判定し、以下のようなパッチを提案します。

```diff
-    mdelay(10); /* Hardware requires a 10ms settling time */
+    msleep(10); /* Optimized: Use sleep instead of busy-wait delay */
```

`msleep` はコンテキストスイッチを伴うため、初期化中の割り込みが無効化されているフェーズやアトミックコンテキストで呼び出すとカーネルパニックを引き起こします。AIは「busy-waitは非効率だからsleepにすべき」という一般的なベストプラクティスを当てはめただけですが、**ハードウェアの仕様やカーネルの実行コンテキストという"暗黙の前提"を理解していません**。

このような「一見正しそうだが、実は致命的なバグを埋め込むパッチ」を人間がいちいちレビューしてリジェクトしなければならないため、限られた人数で運用されているメンテナーのレビュー帯域が圧迫されてしまいました。

## 新ポリシー：非公開報告の禁止と「Assisted-by:」タグの導入

この事態に対し、Linus Torvalds氏はAI生成パッチによる「無意味な攪乱」を厳しく批判し、明確な運用ポリシーの変更を宣言しました。

### 1. 非公開報告（Private Report）の禁止
セキュリティ脆弱性などは通常、影響を最小限に抑えるため非公開のセキュリティ窓口（`security@kernel.org`）に報告されます。しかし、Linus氏は**「現在のAIツールが発見できるようなバグは、すでに周知の事実であるか、公開の場で議論すべきレベルのものである」**とし、AI発見のバグ報告を非公開ルートに流し込むことを禁止しました。

これは、自動化されたスクリプトから大量の「偽陽性（False Positive）のセキュリティアラート」が送りつけられ、セキュリティチームが本来の深刻な脆弱性対応に集中できなくなるのを防ぐためです。

### 2. 「Assisted-by:」タグの義務化と人間の責任
Linuxカーネル開発では、コードの出所と責任を明確にするために Developer's Certificate of Origin (DCO) に基づく `Signed-off-by:` タグが極めて重要な意味を持ちます。今回のアップデートにより、AIの支援を受けて生成・修正されたコードには、新たに **`Assisted-by:`** タグの付与が義務付けられました。

```text
Fix a potential race condition in the XYZ driver

The current implementation in XYZ driver does not lock the
buffer when updating the ring pointer, leading to a potential
race condition under heavy I/O load.

This patch introduces a spinlock around the ring pointer update.

Assisted-by: Claude 4.8 Opus
Signed-off-by: Taro Yamada <taro.yamada@example.com>
```

これにより、**「AIはあくまでアシスタントであり、最終的なコードの正確性に対する説明責任は人間（Signed-off-byを付けた者）にある」**ことが再定義されました。AIが出力したコードをそのまま横流しするだけの貢献は受け入れない、というコミュニティの強い意思表示です。

## 実運用への応用：AIエージェント開発者への技術的示唆

今回の一連の流れは、Linuxカーネルに限らず、すべてのOSSプロジェクトや企業内のプライベートリポジトリにも波及する可能性が高い重要な転換点です。自律型AIエージェント（OpenClaw等）を開発・運用するエンジニアにとって、「いかにノイズを減らし、品質を担保するか」というアーキテクチャの設計が今後のコア課題になります。

### 1. レビュアーの負担（Churn）を意識したスコアリング機構
コードを修正できるからといって、すべてPRとして投げるのはアンチパターンです。エージェント内に「提案の価値」をスコアリングするゲートウェイを設けるべきです。

```python
# CI/CDパイプラインにおけるAIエージェントの評価ロジック例
def evaluate_patch_proposal(patch: Patch, context: RepositoryContext) -> ProposalDecision:
    score = 0
    # 1. 影響範囲とリスクの評価
    if patch.modifies_core_api() and not patch.includes_tests():
        return ProposalDecision.REJECT("コアAPIの変更にはテストが必須です")
        
    # 2. 過去のコンテキストの確認 (git blame / log)
    if "intentional" in context.get_blame_comments(patch.target_lines):
        return ProposalDecision.REJECT("意図的な実装（ワークアラウンド）の可能性が高いです")
        
    # 3. 変更の有意性スコア
    if patch.is_pure_style_fix():
        score -= 50  # 単なるスタイル修正は優先度を下げる
    if patch.fixes_known_cve():
        score += 100
        
    if score > THRESHOLD:
        return ProposalDecision.APPROVE
    else:
        return ProposalDecision.SILENT_LOG
```

影響範囲、テストカバレッジ、過去の変更履歴（`git blame`）をAIに解釈させ、「人間に提案する価値があるか」をエージェント自身にスコアリングさせる仕組みが必須になります。

### 2. CI/CDでのAIコンプライアンスチェック
チーム開発においては、PRのテンプレートやCI（GitHub Actionsなど）で、AI利用の申告を強制する仕組みを導入することが推奨されます。

```yaml
# .github/workflows/check-ai-tags.yml
name: Enforce AI Tags
on:
  pull_request:
    types: [opened, edited, synchronize]

jobs:
  check-tags:
    runs-on: ubuntu-latest
    steps:
      - name: Check for Assisted-by tag if AI was used
        run: |
          # PR本文にAIツールの名前が含まれているかチェック
          if grep -iqE "(claude|chatgpt|copilot|gemini)" <<< "${{ github.event.pull_request.body }}"; then
            # コミットメッセージに Assisted-by があるか確認
            if ! git log --format=%B -n 1 ${{ github.event.pull_request.head.sha }} | grep -qi "Assisted-by:"; then
              echo "Error: AIツールを使用した場合はコミットメッセージに 'Assisted-by:' を含めてください。"
              exit 1
            fi
          fi
```

## まとめ

Linuxカーネルコミュニティが直面した「AI Slop」問題とそれに対する新しいタグ付けの運用は、AIとソフトウェアエンジニアリングが共存するための過渡期を象徴しています。私たちがAIツールを開発・利用する際も、「ただ自動化する」だけでなく、「コミュニティの運用キャパシティに配慮した設計」と「人間による説明責任の担保」を心掛ける必要があります。