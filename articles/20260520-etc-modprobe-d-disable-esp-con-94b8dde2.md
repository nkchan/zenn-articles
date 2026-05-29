---
title: "AIが見つけたLinuxカーネルの致命的脆弱性『Fragnesia』(CVE-2026-46300)の深層：Dirty Fragの再来と対策"
emoji: "🛡️"
type: "tech"
topics:
  - "linux"
  - "kernel"
  - "security"
  - "ai"
  - "network"
published: true
---

2026年5月、Linuxカーネルに極めて深刻なローカル特権昇格（LPE）の脆弱性**「Fragnesia」（CVE-2026-46300）**が発見されました。この脆弱性は、かつて世界を震撼させた「Dirty COW」を彷彿とさせるものであり、リードオンリーのファイルシステムキャッシュをメモリ上で改ざんすることを可能にします。

特筆すべきは、この脆弱性が**AIエージェントによる自律的なバグハンティング**の過程で特定されたという点です。本記事では、Fragnesiaの技術的メカニズムと、なぜAIがこの複雑なリグレッションを発見できたのか、そしてシステム管理者が取るべき対策について深掘りします。

## Fragnesiaの正体：Dirty Fragの「忘れ形見」

Fragnesiaは、以前に修正された脆弱性**「Dirty Frag」（CVE-2026-43284）**の修正漏れ（バリアント）に起因します。

### 技術的な背景
Linuxカーネルのネットワークスタックにおいて、パフォーマンス向上のために`splice()`システムコールなどを用いて、ファイルキャッシュ（Page Cache）のデータをコピーせずにそのまま送信バッファ（skb: socket buffer）として扱う「ゼロコピー」機構が存在します。

Dirty Fragの修正において、このような「共有されたフラグメント」を識別するために、`skbuff`構造体に`SKBFL_SHARED_FRAG`というフラグ（マーカー）が導入されました。

### 脆弱性の核心：マーカーの伝搬漏れ
Fragnesia（CVE-2026-46300）の根本原因は、`net/core/skbuff.c`内の**`skb_try_coalesce()`**関数にあります。

この関数が複数のバッファを結合（Coalesce）する際、**ソース側のバッファが持っていた`SKBFL_SHARED_FRAG`マーカーを、結合後のバッファに正しく引き継がない（伝搬させない）**というバグが存在しました。

1. **マーカーの消失**: `skb_try_coalesce()`によってバッファが結合されると、そのデータが「Page Cache由来の共有データである」という情報が失われます。
2. **セキュリティチェックのバイパス**: IPsec（ESP）などの受信パスでは、`skb_has_shared_frag()`をチェックして、共有データであればCopy-On-Write（CoW）を強制する安全装置があります。しかし、マーカーが消失しているため、このチェックをすり抜けます。
3. **インプレース復号**: 本来CoWが必要な共有ページに対して、カーネルは「自分専用のバッファ」と誤認し、**AES-GCMの復号処理をメモリ上のPage Cacheに対して直接（In-place）実行**してしまいます。

### 攻撃シナリオ
攻撃者は、`su`バイナリなどの重要な実行ファイルを`splice()`でネットワークソケットに流し込み、特定のデータをパケットとして受信させます。カーネルが「復号」という名目でPage Cacheを上書きすることで、メモリ上の`su`バイナリをルートシェルを起動するコードに書き換えることが可能になります。

## なぜAIがこのバグを見つけられたのか

Fragnesiaという名称は、Fragment（断片）とAmnesia（健忘症：マーカーを忘れること）を掛け合わせたものですが、これをAIが発見したことは象徴的です。

1. **リグレッションへの追従能力**: 人間の開発者は「修正パッチを当てた」ことで安心しがちですが、AIはパッチによって導入された新しい状態遷移やフラグの挙動を、既存の複雑なパス（今回の場合はバッファ結合）と網羅的に突き合わせる能力に長けています。
2. **決定論的ロジックの追求**: Fragnesiaはレースコンディション（競合状態）ではなく、特定の条件下で必ず発生する「論理バグ」でした。AIエージェントはコードベースの全パスをスキャンし、`SKBFL_SHARED_FRAG`がどこでセットされ、どこで消えうるかを静的・動的解析を組み合わせて執拗に追跡しました。

## システム管理者が取るべき対策

カーネルのアップデートが最優先ですが、即時の再起動が困難な場合には以下の緩和策が有効です。

### 1. 脆弱なモジュールの無効化
Fragnesiaの悪用には、IPsec（ESP）やRXRPCなどの特定のプロトコルスタックが必要です。これらを使用していないサーバーでは、モジュールをブラックリスト化することで攻撃表面を封鎖できます。

```bash
# /etc/modprobe.d/disable-esp.conf を作成
echo "install esp4 /bin/true" > /etc/modprobe.d/disable-esp.conf
echo "install esp6 /bin/true" >> /etc/modprobe.d/disable-esp.conf
echo "install rxrpc /bin/true" >> /etc/modprobe.d/disable-esp.conf

# 適用（ロード済みの場合）
rmmod esp4 esp6 rxrpc 2>/dev/null || true
```

### 2. 非特権ユーザーによる User Namespace の制限
攻撃のセットアップにはネットワークNamespace等の作成が必要になることが多いため、多層防御として有効です。

```bash
sysctl -w kernel.unprivileged_userns_clone=0
```

## 考察とまとめ

Fragnesiaの教訓は、**「一度修正されたはずの脆弱性の周辺には、類似の亜種が潜んでいる」**という普遍的な事実です。特に、パフォーマンスとセキュリティがトレードオフになりやすいPage Cache周辺のロジックは、今後もAIと人間による熾烈な調査対象となるでしょう。

2026年以降、我々エンジニアに求められるのは、単にパッチを当てるだけでなく、AIが報告してくる「論理的な矛盾」を正しく解釈し、システム全体のアーキテクチャとして「不要な機能（攻撃ベクトル）を最小化する」運用設計の重要性がより一層高まっています。

---

### 参考リンク
- [The Hacker News: AI Agents Discover Critical Linux Kernel Vulnerability](https://thehackernews.com/)
- [Security Affairs: Fragnesia LPE Flaw in Linux Kernel](https://securityaffairs.com/)
- [TuxCare: Understanding CVE-2026-46300](https://tuxcare.com/)
