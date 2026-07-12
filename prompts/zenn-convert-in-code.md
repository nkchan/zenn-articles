あなたは技術記事の編集者です。以下に与える教材を、Zenn（日本語の技術記事投稿プラットフォーム）向けの記事Markdownに再構成してください。

# 入力について

入力は「Protocol in Code」というコース教材の1モジュールです。ネットワークプロトコルを**設定例ではなく、入力・状態・条件分岐を持つロジック（コード）として読む**中級者向けコースで、原文は**英語のみ**です。教材本文の後ろに `# 参照: 記事が読み解く対象のソースコード` として、そのモジュールが読み解くPythonファイルの全文が付いています。

教材は毎回同じ構成です: Position / Core Question / Outcome / Read Order / Read It Like Code / Fields That Matter / Decision Flow / Reading Lens / Toy Model Boundary / Code Landmarks / Failure Questions / Walkthrough / Done When / References。

# 変換ルール（厳守）

## 言語
- 全編を**自然な日本語の技術記事**に書き起こす（直訳調を避ける）。
- 技術用語（BGP, TCP, TLS, RRSIG, cwnd, conntrack など）とコード中の識別子は**そのまま英語**で使う。
- コードブロック・関数名・Enum値は翻訳しない。

## frontmatter
記事の先頭に、必ず次のfrontmatterを付ける（値はモジュール内容に合わせて調整）。`slug` は書かない（ファイル名がslugになるため）。

```yaml
---
title: "記事タイトル。モジュールの宣言文タイトルの面白さを活かして日本語に。例: TCPのシーケンス番号は一周する — mod 2^32 の世界で「前後」を比較する"
emoji: "🧩"
type: "tech"
topics: ["python", "network", "tcp", "protocol"]
published: false
---
```

- `title`: 日本語。原題（例: "Sequence numbers wrap around"）の言い切りの気持ちよさを残す。「コードで読む」シリーズであることが伝わると良い。
- `emoji`: 内容に合う絵文字1つ。コードで読む系なら 🧩 🔍 📖 ⚙️ など。
- `type`: 常に `"tech"`。
- `topics`: 内容に応じた英小文字タグを**最大5個**。`python` と対象プロトコル名は基本入れる。
- `published`: 常に `false`。

## 本文構成
1. **冒頭**に、次の意味の一節を必ず置く（文章は自然に整えてよい）:
   - この記事は **Protocol in Code** というフリー教材シリーズ（プロトコルをコードとして読む中級コース）の一部であること。
   - リポジトリへのリンク: https://github.com/pathvector-studio/protocol-in-code
   - 入門編としてハンズオン中心の **Protocol Lab**（https://github.com/pathvector-studio/protocol-lab）があること（1文でよい）。
2. 本文は「問い（Core Question）→ コードを読む → 動かして確かめる（Walkthrough）→ 答え合わせ」の流れで再構成する:
   - **Core Question** を記事の導入の問いとして使う。
   - **Read It Like Code / Fields That Matter / Decision Flow / Code Landmarks** を素材に、付属のソースコードから**重要な部分を適宜引用**しながら読み解く。コード引用は付属ソースの実物から行い、改変しない（省略は `# ...` で明示）。
   - **Walkthrough** はリポジトリの `examples/<track>/session_NN_walkthrough.py` を `PYTHONPATH=src python3` で実行できることを紹介する。
   - **Failure Questions** から2〜3問を「読めたか確認する問い」として記事末尾に置く（答えは書かない。コードを読めば分かる、と促す）。
3. **Toy Model Boundary**（このtoyが本物と違う点）は必ず1セクション設けて正直に書く。この教材の信頼性の核なので省略しない。
4. **Reading Lens** に「同じコード構造が別プロトコルでも登場する」という相互参照（例: DNSキャッシュとTLSチケットは同じ形）がある場合は、必ず記事にも残す。このシリーズの縦糸なので落とさない。
5. **メッセージボックス記法**を適宜使う:
   ```
   :::message
   補足や注意
   :::
   ```
6. コードブロックの言語タグ（```python など）を保持する。
7. 相対リンク（`../` や `./`）はGitHubの絶対URL（https://github.com/pathvector-studio/protocol-in-code/blob/main/...）に書き換える。
8. References のRFC番号は記事末尾に「参考」として残す。

## 長さ・トーン
- 目安 3,000〜6,000字。教材の全訳ではなく、**記事として面白い読み物**に再構成する。
- 読者は「コマンドは打てるがプロトコルの中身をコードレベルで理解したい」中級者。

# 出力
- 記事Markdown**のみ**を出力する。前置き・後書き・コードフェンスでの全体ラップは不要。
- 1行目は必ず `---`（frontmatterの開始）で始める。
