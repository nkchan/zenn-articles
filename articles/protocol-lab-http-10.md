---
title: "HTTP/1.1の1往復を平文で読む——200 / 304 / 404 と Cache-Control・ETag"
emoji: "🌐"
type: "tech"
topics: ["http", "network", "curl", "containerlab", "rfc9110"]
published: true
---

この記事は、ネットワークプロトコルを手を動かして学ぶフリー教材シリーズ **Protocol Lab** の一部です。教材本体（実行スクリプト・サンプル設定・RFCノート）はGitHubで公開しています。

- リポジトリ: https://github.com/pathvector-studio/protocol-lab

TCP はバイトを運び（[Lab 07](https://zenn.dev/nkchan/articles/protocol-lab-tcp-07)）、TLS はそれを包めました（[Lab 09](https://zenn.dev/nkchan/articles/protocol-lab-tls-09)）。今回はバイトそのもの——1つの HTTP/1.1 リクエストとレスポンスを**平文**で見て、各行に名前を付けられるようにします。

4種類のリクエストを送って各結果を読みます。

- `GET /` → **200 OK**（`Cache-Control` と `ETag` 付き）
- `HEAD /` → **200**（ヘッダのみ、body なし）
- `If-None-Match` 付き `GET /` → **304 Not Modified**（キャッシュはまだ新鮮）
- `GET /missing` → **404 Not Found**

最終的に、次のやり取りにラベルを付けられる状態を目指します。

```text
> GET / HTTP/1.1            <- request line: method, target, version
> Host: 10.0.0.2:8080       <- request header
>
< HTTP/1.1 200 OK           <- status line
< Content-Type: text/plain; charset=utf-8
< Content-Length: 40
< Cache-Control: max-age=60 <- キャッシュが再利用してよい時間
< ETag: "v1-abc123"         <- 条件付きリクエスト用の validator
<
Hello from the Protocol Lab HTTP server.
```

想定時間は45〜60分です。

## このLabで学べること

- HTTP message の形: start line / headers / 空行 / body。
- GET と HEAD が何をするか、HEAD が GET とどう違うか。
- status code の 2xx / 3xx / 4xx への分類と、200 / 304 / 404 の意味。
- `Cache-Control` と `ETag` の用途。
- 条件付きリクエスト（`If-None-Match`）が `304 Not Modified` を生み、body を節約する仕組み。

今回は扱いません: HTTP の上の HTTPS/TLS（Lab 09）、HTTP/2 の framing / multiplexing（Lab 11）、完全なキャッシュ実装や `Vary`、Cookie / 認証 / リダイレクトの詳細。

## RFCで読む場所

HTTP の現行仕様は RFC 9110-9112（2022）です。

| RFC | 読むポイント |
|---|---|
| RFC 9110 §3, §6 | resource / representation / message の考え方 |
| RFC 9110 §9 | methods（GET / HEAD の定義） |
| RFC 9110 §15 | status codes（200 / 304 / 404 の意味） |
| RFC 9111 §5.2 | `Cache-Control` ディレクティブ |
| RFC 9111 §4.3 | validation と conditional request（`ETag` / `If-None-Match` / 304） |
| RFC 9112 §2-3 | HTTP/1.1 の message 構文 |

## 実験の全体像

Lab 07 と同じ2ノード。server は小さな Python HTTP サーバで、TLS は使わず平文で観察します。

```text
client (10.0.0.1) ------ eth1/eth1 ------ server (10.0.0.2:8080)
                                          GET /  -> 200 (+Cache-Control, ETag)
                                          If-None-Match -> 304
                                          /missing -> 404
```

両ノードとも `nicolaka/netshoot`（`curl`・`python3`・`tcpdump` 同梱）を使います。

## 手順

```bash
./scripts/labctl.sh run http-10   # deploy → HTTPサーバ起動 → 4種のcurl → 確認 → 後片付け
```

以下は手動手順です。

### 1. 起動する

```bash
cd protocol-lab/examples/http-10
cat server/app.py
sudo containerlab deploy -t http-10.clab.yml
docker exec -d clab-http-10-server python3 /app/app.py
```

### 2. GET /（200 と cache header）

```bash
docker exec clab-http-10-client curl -v http://10.0.0.2:8080/
```

```text
> GET / HTTP/1.1
> Host: 10.0.0.2:8080
< HTTP/1.1 200 OK
< Content-Type: text/plain; charset=utf-8
< Content-Length: 40
< Cache-Control: max-age=60
< ETag: "v1-abc123"
```

`>` が送ったリクエスト、`<` が返ってきたレスポンス（curl の表記）です。

### 3. HEAD /（ヘッダのみ）

```bash
docker exec clab-http-10-client curl -v -I http://10.0.0.2:8080/
```

`HEAD` は `GET` と同じヘッダを返しますが、body は返しません。`Content-Length` は付くが本文は空です。

### 4. 条件付き GET（304）

さっき見た `ETag` を `If-None-Match` に入れて、もう一度 `GET`。

```bash
docker exec clab-http-10-client curl -v -H 'If-None-Match: "v1-abc123"' http://10.0.0.2:8080/
```

```text
< HTTP/1.1 304 Not Modified
< ETag: "v1-abc123"
< Cache-Control: max-age=60
```

`304` は「あなたが持っているコピーはまだ新しい。body は送らない」。これでネットワークとサーバの負荷を減らせます。

### 5. 存在しないパス（404）

```bash
docker exec clab-http-10-client curl -v http://10.0.0.2:8080/missing
# < HTTP/1.1 404 Not Found
```

### 6. 平文であることを capture で確かめる

```bash
docker exec clab-http-10-client sh -c \
  "tcpdump -i eth1 -A -s0 'tcp port 8080' & sleep 1; curl -s http://10.0.0.2:8080/ >/dev/null; sleep 1; pkill tcpdump"
```

`-A` でペイロードを ASCII 表示すると、`GET / HTTP/1.1` や `HTTP/1.1 200 OK` がそのまま読めます。TLS がないので、経路上の観測者に中身が見えます（Lab 09 との対比）。

## なぜそう動くのか

HTTP は「リソースの representation を request/response でやり取りする」プロトコルです。1つの message は start line（request line か status line）、header 群、空行、body の順です。

- **method** は「何をしたいか」。`GET` は取得、`HEAD` は「ヘッダだけ欲しい」。だから HEAD は転送量を節約して存在確認やサイズ確認に使える。
- **status code** は結果の分類。`2xx` 成功、`3xx` さらなるアクション、`4xx` クライアント側の問題。`200` 取得成功、`404` 無い、`304` 変わっていない。
- **cache header**: `Cache-Control: max-age=60` は「60秒はそのまま再利用してよい」（鮮度）。`ETag` はその representation の識別子（validator）。
- **conditional request**: 次回 `If-None-Match: <etag>` を付けて聞くと、同じなら `304`（body なし）、変わっていれば `200` と新しい body。これで「変わっていないものを再送しない」を実現する。

要点は、HTTP のセマンティクス（method / status / header）が、下の TCP・TLS とは独立した層として読めることです。

## よくある誤解

- **HEAD が body を返すと思う**。HEAD はヘッダのみ。`Content-Length` は付くが本文はない。
- **304 を「エラー」と読む**。304 は成功的な最適化。「変わっていないから送らない」。
- **`Cache-Control` と `ETag` の役割を混同する**。`max-age` は「どれだけ再利用してよいか（鮮度）」、`ETag` は「同じかを確かめる印（validation）」。
- **curl が自分でキャッシュすると思う**。curl はキャッシュしない。ここで見せているのは cache の**仕組み**。ブラウザや CDN がこれを使う。
- **`Host` header**。HTTP/1.1 では必須。1つの IP で複数サイトを見分ける（SNI の HTTP 版のような役割）。

## 確認問題

1. HTTP message の構成要素は何か（start line 以降）。
2. GET と HEAD は何が違うか。HEAD は何に使えるか。
3. 200 / 304 / 404 はそれぞれ何を意味し、どのグループか。
4. `Cache-Control: max-age=60` と `ETag` は、それぞれ何のためにあるか。
5. 条件付き `GET` はどんなときに `304` を返すか。何を節約できるか。
6. この Lab の通信はなぜ capture で読めるのか。Lab 09 とどう違うか。

## 後片付け

```bash
sudo containerlab destroy -t http-10.clab.yml --cleanup
```

---

**Protocol Lab について**

この記事は、ネットワークプロトコルを手を動かして学ぶフリー教材シリーズ Protocol Lab の一部です。全Labの一覧・実行スクリプト・RFCノートはこちらにあります。

- シリーズ一覧 / リポジトリ: https://github.com/pathvector-studio/protocol-lab

役に立ったら、リポジトリに ⭐️ をいただけると励みになります。

次回は同じ HTTP を HTTP/2 と QUIC で見て、フレーミングとストリーム多重化を観察します（QUIC Lab 11）。
