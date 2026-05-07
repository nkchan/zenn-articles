---
title: "retrieval-policy.yaml"
emoji: "🤖"
type: "tech"
topics:
  - "ai"
  - "network"
published: false
---

index:
  chunking:
    size: 700
    overlap: 120
  metadata_keys:
    - domain        # 例: support, legal, product
    - status        # draft, review, final
    - locale        # ja, en
    - updated_at    # ISO8601

query:
  filters:
    status: final
    locale: ja
  top_k: 8
  rerank: true

generation:
  require_citation: true
  citation_granularity: page
  abstain_if_no_evidence: true
```

このポリシーで重要なのは、`require_citation` と `abstain_if_no_evidence` を同時に有効化することだ。根拠が弱い回答を“それっぽく出す”挙動を抑制できる。ユーザー体験としては短期的に回答率が下がるが、長期的な信頼性は確実に上がる。

加えて、メタデータは「あとで使うかも」ではなく、最初からクエリ条件に使う前提で設計する。タグ付けコストが気になる場合でも、`status` と `domain` だけは先に固定した方がよい。ここを曖昧にすると、後段の評価基盤（正解データ作成・A/B比較）が崩れる。

## 運用で詰まりやすいポイントと回避策

第一に、マルチモーダル化で「何でも入れれば賢くなる」と考えるのは危険である。画像資産は内容の粒度差が大きく、検索意図とズレることがある。まずはユースケースを限定し、図表・UI・写真を分けて評価セットを作るべきだ。

第二に、メタデータの更新遅延が品質事故を生む。`status=final` への遷移が遅れれば古い情報が混ざる。CI/CDやドキュメント更新フローにメタデータ更新を組み込み、文書版管理と同時に処理するのが安全である。

第三に、引用があるだけで正しいとは限らない。ページ引用は「根拠の位置」を示すが、「解釈の正しさ」までは保証しない。生成フェーズでの制約（引用外の断定禁止、数値比較時の原文再確認）をルール化する必要がある。

コミュニティ側でも、managed RAGの文脈では「コンテキスト運用コスト」や「実運用の単純性」が繰り返し議論されている。実際、HNの関連スレッドでも“コード最適化ではなくコンテキスト最適化に時間を使う”という指摘があり、今回のアップデートはこの運用コストを下げる方向と整合的である。

## 考察

今回のアップデートを一言で言うと、「RAGの実装難易度を下げる」ではなく「RAGの運用難易度を下げる」進化である。PoC段階ではモデル性能やデモ精度に注目しがちだが、本番導入で効くのは、検索スコープ統制と根拠トレースの仕組みだ。ここにAPIが踏み込んだ価値は大きい。

Kaoru視点で重要なのは、これを“便利な新機能”で終わらせず、評価可能な開発プロセスに接続することだ。具体的には、(1)ユースケース別評価セット、(2)メタデータ契約、(3)引用付き回答の品質ゲートを先に定義する。これができれば、モデル更新やプロンプト変更が入っても品質の後退を検知できる。

また、Protocol Lab的な教材化にも向いている。RAGはネットワークほど低レイヤではないが、情報伝搬の信頼性設計という意味で共通する。検索（取得）、生成（変換）、引用（検証）の3層を分離して考える設計は、BGPで言えば経路取得・選好・検証を分ける感覚に近い。実務教育に転用しやすい題材である。

## まとめ

Gemini API File Searchのマルチモーダル化は、RAGの“作る難しさ”より“運用する難しさ”に効くアップデートだった。特にカスタムメタデータとページ引用は、品質管理・監査・デバッグの3点で即効性がある。

次のアクションとしては、まず小さな業務コーパスで `status/domain` フィルタと引用必須ルールを導入し、回答率より再現性を優先して評価するのがよい。RAGはモデル選定より、データ契約と運用設計で勝負が決まる。

## 参考

- [Gemini API File Search is now multimodal: build efficient, verifiable RAG](https://blog.google/innovation-and-ai/technology/developers-tools/expanded-gemini-api-file-search-multimodal-rag/)
- [Introducing the File Search Tool in Gemini API](https://blog.google/innovation-and-ai/technology/developers-tools/file-search-gemini-api/)
- [Hacker News Algolia: Gemini API File Search](https://hn.algolia.com/api/v1/search?query=Gemini%20API%20File%20Search&tags=story)
- [Hacker News Algolia: comments on managed Gemini RAG thread](https://hn.algolia.com/api/v1/search?tags=comment,story_46766432)