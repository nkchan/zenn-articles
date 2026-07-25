---
title: "DANE入門: DNSに証明書を保証させる — CAなしで自己署名証明書を信頼し、なりすましを弾く"
emoji: "🔐"
type: "tech"
topics: ["dane", "dnssec", "tls", "network", "containerlab"]
published: true
---

この記事は、ネットワークプロトコルを手を動かして学ぶフリー教材シリーズ **Protocol Lab** の一部です。各Labは、実際にコンテナでプロトコルを動かし、パケットや出力を自分の目で確かめながら「なぜそう動くのか」を言葉にできるようになることを目指しています。

- リポジトリ: https://github.com/pathvector-studio/protocol-lab

今回は **Lab #17: DANE — DNSが証明書を保証するとき** を扱います。想定時間は55〜70分です。

## この記事のゴール

通常、TLS クライアントは **認証局(CA)** が署名したという理由で証明書を信じます（TLS の証明書検証については Lab 09 で扱っています）。

**DANE** は、これとは別の「信頼の起点」を与える仕組みです。ドメイン所有者が DNS に **TLSA** レコードを載せて証明書を pin（固定）し、**DNSSEC**（Lab 13）がそのレコードを信頼できるものにします。CA は不要 —— DNS 自身が証明書を保証するのです。

このLabは、Lab 13（DNSSEC）と Lab 09（TLS 証明書）を1本につなぎます。流れはこうです。

- DNSSEC で署名済みの `example.lab` が、`_443._tcp.www.example.lab` に対する **TLSA** レコードを公開し、web サーバの証明書を pin する。
- client はその TLSA を取得する。TLSA には **RRSIG**（DNSSEC 署名）が付いているので信頼できる。この TLSA に対して web サーバの **自己署名** 証明書を検証すると → **一致**し、`Verify return code: 0`。
- 別の証明書を持つ **なりすまし(impostor)** サーバを同じ TLSA と照合すると → **拒否**され、`no matching DANE TLSA records`。

読み終える頃には、次の表を自分の言葉で説明できるようになっているはずです。

| サーバ | 証明書 | 署名済み TLSA との照合 | 結果 |
|---|---|---|---|
| 本物の web (`:443`) | 自己署名。鍵が TLSA に pin されている | 一致する | `Verify return code: 0 (ok)` |
| なりすまし (`:8443`) | 別の鍵 | 一致しない | `65 (no matching DANE TLSA records)` |

## この記事で学べること

- **TLSA** レコードとは何か。そして `_port._proto.name` という命名がどう機能するか。
- `3 1 1` というセレクタの意味（DANE-EE / SubjectPublicKeyInfo / SHA-256）。
- **なぜ DANE は DNSSEC とセットでしか意味を持たないのか** —— 署名されていない TLSA は偽装できてしまう。
- DANE によって **自己署名** 証明書がどうして信頼できるようになるのか（CA の仕事を DNS が肩代わりする）。
- 公開された TLSA に一致しない証明書が、たとえ一見正しく見えても拒否されるのはなぜか。

一方、このLabでは次の内容は扱いません。

- SMTP 向けの DANE（RFC 7672）やその他のアプリケーションプロファイル。
- 証明書用途(usage) `3`（DANE-EE）以外のモードや、`1 1` 以外の selector / matching。
- client 側で完全な DNSSEC 検証リゾルバを経由すること（このLabでは権威サーバから直接 RRSIG を読み取ります。検証リゾルバを経由すれば Lab 13 のように AD フラグが立ちます）。

## RFC で読む場所

| RFC | 章 | 読むポイント |
|---|---|---|
| RFC 6698 | 2 | TLSA レコードの構造(usage / selector / matching type) |
| RFC 6698 | 3 | `_port._proto.name` の命名、DANE の使い方 |
| RFC 7671 | 4-5 | DANE の運用上の更新(DANE-EE `3` の推奨など) |
| RFC 4034 | 3 | RRSIG（TLSA も署名される。Lab 13 の復習） |
| RFC 5737 | 3 | Lab で使うアドレスが documentation 用であること |

## 実験の全体像

登場するのは3台です。client 1台、auth（DNSSEC 署名済みの `example.lab` を配信、TLSA を含む）1台、web（TLSA が pin する証明書を持つ TLS サーバ）1台。

```text
auth (10.0.1.2) --- eth1 --- client --- eth2 --- web (10.0.2.2)
  BIND, signed             dig +dnssec TLSA      openssl s_server
  example.lab + TLSA       openssl s_client-dane :443 real / :8443 impostor
```

client は auth から TLSA を引き（RRSIG 付き）、web の証明書をその TLSA と照合します。`:443` は TLSA が pin した本物、`:8443` は別鍵のなりすましです。

```mermaid
sequenceDiagram
  participant C as client
  participant A as auth (DNSSEC-signed)
  participant W as web

  C->>A: _443._tcp.www.example.lab TLSA? (+dnssec)
  A-->>C: TLSA 3 1 1 <hash> + RRSIG
  Note over C: TLSA is signed -> trustworthy (Lab 13)
  C->>W: TLS to :443 (real cert)
  W-->>C: Certificate (self-signed)
  Note over C: SPKI hash == TLSA -> matched, Verify 0
  C->>W: TLS to :8443 (impostor cert)
  W-->>C: Certificate (different key)
  Note over C: hash != TLSA -> no matching DANE TLSA records
```

:::message
`203.0.113.0/24` は使いませんが、`10.0.1.0/24` と `10.0.2.0/24` はローカル閉域です。RFC 5737 の documentation 用アドレスを使うので、実際のインターネットへは何も広告しません。
:::

## 必要なもの

推奨環境:

- Linux / WSL2 / Linux VM
- Docker
- containerlab

使用イメージ:

- `protocol-lab/bind9:9.20`（`examples/dane-17/Dockerfile` からローカルビルド。auth 用）
- `nicolaka/netshoot:latest`（client と web。`dig`、`openssl` 同梱）

証明書とゾーン署名は `run.sh` が実行時に行います（web 証明書 → TLSA 計算 → ゾーン署名）。リポジトリには何もコミットしません。openssl の DANE 検証（`-dane_tlsa_rrdata`）を使います。

## 実行手順

いちばん手っ取り早いのは、ラッパースクリプトに任せる方法です。

```bash
./scripts/labctl.sh run dane-17
```

`labctl.sh run dane-17` は、deploy、web 証明書の生成と TLSA 計算、TLSA 入りゾーンの DNSSEC 署名、TLSA の取得、本物証明書の DANE 検証（一致）、なりすましの DANE 検証（拒否）、そして後片付けまでを一気に行います。

以下では、内部で何が起きているのかを1ステップずつ手で追っていきます。

### 1. 作業ディレクトリへ移動する

```bash
cd protocol-lab/examples/dane-17
```

### 2. web の証明書と TLSA を作る

```bash
sudo containerlab deploy -t dane-17.clab.yml
# web: 本物 + なりすまし用の自己署名証明書
docker exec clab-dane-17-web sh -c \
  "openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/real.key -out /tmp/real.crt -subj '/CN=www.example.lab' -addext 'subjectAltName=DNS:www.example.lab' -days 3650"
# TLSA (3 1 1) = DANE-EE / SPKI / 本物証明書の SHA-256
docker exec clab-dane-17-web sh -c \
  "openssl x509 -in /tmp/real.crt -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256"
# TLS サーバ: 本物を :443、なりすましを :8443 で待ち受ける
docker exec -d clab-dane-17-web sh -c "openssl s_server -accept 443 -cert /tmp/real.crt -key /tmp/real.key -www -quiet"
```

ここで計算した SHA-256 ハッシュが、そのまま TLSA レコードの pin になります。

### 3. TLSA 入りゾーンを DNSSEC 署名する

`example.lab` に `_443._tcp.www.example.lab. IN TLSA 3 1 1 <hash>` を入れ、Lab 13 と同じ手順で署名して auth に読ませます（`run.sh` が自動でやります）。

```text
_443._tcp.www.example.lab. 300 IN TLSA 3 1 1 <hash>
_443._tcp.www.example.lab. 300 IN RRSIG TLSA ...   <- DNSSEC 署名
```

### 4. TLSA を取得する（署名付き＝信頼できる）

```bash
docker exec clab-dane-17-client dig +dnssec @10.0.1.2 _443._tcp.www.example.lab TLSA
```

`TLSA 3 1 1 ...` と、その隣に `RRSIG TLSA ...` が返ってきます。RRSIG があるので、この pin は DNSSEC で守られています。

### 5. 本物の証明書を DANE で検証する（CA 不要）

```bash
RR=$(docker exec clab-dane-17-client dig +short @10.0.1.2 _443._tcp.www.example.lab TLSA | head -1)
docker exec clab-dane-17-client sh -c \
  "echo Q | openssl s_client -connect 10.0.2.2:443 -dane_tlsa_domain www.example.lab -dane_tlsa_rrdata '$RR'"
```

見るポイント:

```text
DANE TLSA 3 1 1 ...<hash> matched the EE certificate at depth 0
Verify return code: 0 (ok)
```

証明書は **自己署名**（CA なし）なのに、`Verify return code: 0`。DNS（DNSSEC 付き）が保証しているからです。

### 6. なりすましを同じ TLSA で検証する（拒否）

```bash
docker exec clab-dane-17-client sh -c \
  "echo Q | openssl s_client -connect 10.0.2.2:8443 -dane_tlsa_domain www.example.lab -dane_tlsa_rrdata '$RR'"
```

見るポイント:

```text
Verification error: no matching DANE TLSA records
Verify return code: 65 (no matching DANE TLSA records)
```

別鍵の証明書は、公開された TLSA と一致しないので拒否されます。

## 期待される出力

- `dig +dnssec ... TLSA`: `TLSA 3 1 1 <hash>` と `RRSIG TLSA`。
- 本物 (`:443`): `matched the EE certificate`、`Verify return code: 0 (ok)`。
- なりすまし (`:8443`): `no matching DANE TLSA records`、`Verify return code: 65`。

## なぜそう動くのか

DANE（DNS-based Authentication of Named Entities）は、「どの証明書が正しいか」を **DNS で宣言する**仕組みです。証明書の信頼を CA ではなく、ドメイン所有者 + DNSSEC に置きます。

- **TLSA レコード**: `_443._tcp.www.example.lab` のように「ポート・プロトコル・ホスト名」で名前を作り、そのサービスが使う証明書を pin します。`3 1 1` は「usage=DANE-EE（end-entity 証明書そのもの）/ selector=SPKI（公開鍵情報）/ matching=SHA-256」を意味します。つまり「この公開鍵の SHA-256 を持つ証明書だけを信じよ」という宣言です。
- **なぜ DNSSEC が必須か**: TLSA が署名されていなければ、攻撃者が偽の TLSA を注入して別の証明書を pin できてしまいます。DNSSEC（Lab 13）の RRSIG が TLSA の真正性を保証して初めて、DANE は安全になります。だから DANE は DNSSEC の上に成り立ちます。
- **CA が要らない**: 通常は「CA が署名 → client が CA を信頼」という経路で証明書を信じます。DANE では「ドメイン所有者が DNS で pin → DNSSEC が保証」という経路になります。だから **自己署名でも**、TLSA と一致すれば信頼できるのです。CA の役割を DNS が肩代わりしています。
- **なりすましが弾かれる理由**: たとえ見た目が正しく、別の CA で署名されていても、公開された TLSA（＝本物の鍵の指紋）と一致しなければ DANE は拒否します。証明書の「すり替え」を、DNS に固定した指紋で検出するわけです。

要点は、**「この名前にはこの証明書」という宣言を、DNSSEC で守られた DNS に置くことで、CA なしに（あるいは CA に加えて）証明書を認証できる**、ということです。

## 詰まりやすい点

:::message
DANE を DNSSEC 抜きで語ってしまうのが最大の落とし穴です。署名のない TLSA は偽装できるので、DANE は DNSSEC（Lab 13）が前提です。
:::

- **TLSA の名前を間違える**。正しくは `_443._tcp.www.example.lab`（ポート・プロトコルが頭に付く）。
- **`3 1 1` の意味**。usage=3（DANE-EE）、selector=1（SPKI）、matching=1（SHA-256）。
- **自己署名を「危険」と決めつける**。DANE の文脈では、TLSA が pin していれば自己署名でも正当です。
- **なりすましが別 CA で署名されていれば通ると思う**。DANE は「公開された指紋と一致するか」だけを見ます。CA は無関係です。
- **AD フラグ**。このLabは auth から直接 TLSA を引くので AD は付きません（RRSIG で署名は確認できます）。検証リゾルバ経由なら Lab 13 のように AD が立ちます。

## 後片付け

```bash
sudo containerlab destroy -t dane-17.clab.yml --cleanup
```

`labctl.sh run dane-17` を使った場合は、スクリプトが最後に destroy します。

## 確認問題

1. TLSA レコードは何を pin するか。名前 `_443._tcp.www.example.lab` の各部分は何を表すか。
2. `3 1 1` の3つの数字はそれぞれ何を意味するか。
3. DANE がなぜ DNSSEC を前提にするのか。署名のない TLSA だと何が問題か。
4. DANE では、自己署名の証明書がなぜ信頼できるのか。CA の役割は誰が担うか。
5. なりすましの証明書が別の有効な CA で署名されていても、この web で拒否されるのはなぜか。
6. このLabで AD フラグが付かないのはなぜか。どうすれば付くか（Lab 13 参照）。

## 検証済み実行ログ (2026-07-07)

このLabは実機で再現性を確認済みです。

実行環境:

- Ubuntu 26.04 LTS (kernel 7.0.0-27-generic, x86_64)
- Docker 29.1.3
- containerlab 0.77.0
- auth: `internetsystemsconsortium/bind9:9.20` (BIND 9.20.24) を薄くラップした `protocol-lab/bind9:9.20`
- client / web: `nicolaka/netshoot:latest` (dig 9.20.23, openssl 3.x)

`PATH="/tmp/pl-shim:$PATH" ./scripts/labctl.sh run dane-17` で deploy → verify → destroy を実行し、`verification.json` は `"status": "verified"` を返しました。web 証明書は実行時に生成し、その公開鍵から TLSA（`3 1 1`）を計算して DNSSEC 署名済みゾーンに載せています。

### TLSA レコードを取得（DNSSEC 署名付き）

```text
$ docker exec clab-dane-17-client dig +dnssec @10.0.1.2 _443._tcp.www.example.lab TLSA

_443._tcp.www.example.lab. 300 IN TLSA  3 1 1 5E26EC745C33B4CACA06BC6BA2AE55E0D5BA0FDDB729616613AC1AAC3D3D82D6
_443._tcp.www.example.lab. 300 IN RRSIG TLSA 13 5 300 20360704090109 20260707090109 12614 example.lab. ...
```

`TLSA 3 1 1 ...` の隣に `RRSIG TLSA`。DNSSEC で署名されているので、この pin は信頼できます。

### 本物の証明書を DANE で検証（自己署名なのに Verify 0）

```text
$ echo Q | openssl s_client -connect 10.0.2.2:443 \
    -dane_tlsa_domain www.example.lab -dane_tlsa_rrdata '3 1 1 5E26...3D3D82D6'

DANE TLSA 3 1 1 ...b729616613ac1aac3d3d82d6 matched the EE certificate at depth 0
Verify return code: 0 (ok)
```

証明書は CA が署名していない（自己署名）にもかかわらず、`Verify return code: 0`。DNSSEC で守られた TLSA が保証しているためです。

### なりすましの証明書を同じ TLSA で検証（拒否）

```text
$ echo Q | openssl s_client -connect 10.0.2.2:8443 \
    -dane_tlsa_domain www.example.lab -dane_tlsa_rrdata '3 1 1 5E26...3D3D82D6'

verify error:num=65:no matching DANE TLSA records
Verify return code: 65 (no matching DANE TLSA records)
```

別鍵の証明書は、公開された TLSA と一致しないので拒否されます。DANE は「DNS に固定した指紋」で証明書のすり替えを検出します —— CA 抜き（あるいは CA に加えて）で。

### Cleanup

```bash
containerlab destroy -t dane-17.clab.yml --cleanup
```

## 参考リンク

- [RFC 6698: The DNS-Based Authentication of Named Entities (DANE) Transport Layer Security (TLS) Protocol: TLSA](https://www.rfc-editor.org/rfc/rfc6698)
- [RFC 7671: The DANE Protocol: Updates and Operational Guidance](https://www.rfc-editor.org/rfc/rfc7671)
- [RFC 4034: Resource Records for the DNS Security Extensions](https://www.rfc-editor.org/rfc/rfc4034)
- [RFC 5737: IPv4 Address Blocks Reserved for Documentation](https://www.rfc-editor.org/rfc/rfc5737)
- [openssl s_client manual page](https://docs.openssl.org/master/man1/openssl-s_client/)
- [DANE / TLSA 補足ノート（rfc-notes）](https://github.com/pathvector-studio/protocol-lab/blob/main/rfc-notes/dane-tlsa.md)
- [DNS Lab 13: DNSSEC の検証](https://github.com/pathvector-studio/protocol-lab/blob/main/examples/dns-13-dnssec-validation.md)
- [TLS Lab 09: 暗号化の前に見えるもの](https://github.com/pathvector-studio/protocol-lab/blob/main/examples/tls-09-handshake-certificates.md)

---

この記事は **Protocol Lab** シリーズの一部です。BGP・DNS・TLS・QUIC など、ネットワークプロトコルを実際に動かして学べるLabが揃っています。

- シリーズ一覧: https://github.com/pathvector-studio/protocol-lab

役に立ったと感じたら、ぜひ GitHub リポジトリに ⭐ スターをお願いします。教材づくりの大きな励みになります。

次回は、DANE を電子メール配送に応用した **SMTP over DANE（RFC 7672）** を取り上げ、MX ホストの TLSA を使ってメールサーバ間の TLS を認証する仕組みを見ていく予定です。