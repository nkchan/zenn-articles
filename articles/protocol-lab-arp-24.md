---
title: "ARPを2台のノードで動かして、IP→MAC解決を自分の言葉で説明できるようになる"
emoji: "🔌"
type: "tech"
topics: ["arp", "network", "containerlab", "ipv4", "ethernet"]
published: true
---

この記事は、ネットワークプロトコルを手を動かして学ぶフリー教材シリーズ **Protocol Lab** の一部です。実際に2台のノードを1本のリンクで繋ぎ、パケットキャプチャを見ながら「なぜそう動くのか」を確かめていきます。

教材リポジトリはこちら 👉 https://github.com/pathvector-studio/protocol-lab

想定時間は 35〜50 分。前提として、以下を先にやっておくとスムーズです。

- [Lab 23: IPv6 Neighbor Discovery](https://github.com/pathvector-studio/protocol-lab/blob/main/labs/ndp-23-neighbor-discovery.md)
- [TCP Lab 07: Handshake / Teardown](https://github.com/pathvector-studio/protocol-lab/blob/main/labs/tcp-07-handshake-teardown.md)

RFC の読みどころは [`rfc-notes/arp-address-resolution.md`](https://github.com/pathvector-studio/protocol-lab/blob/main/rfc-notes/arp-address-resolution.md) にまとめてあります。

## ゴール

Lab 23 では、IPv6 が近隣ノードの MAC アドレスをどう見つけるか（NDP）を見ました。この Lab では、それが置き換えた **IPv4 の原型**、**ARP**（Address Resolution Protocol）を扱います。

仕事は同じで、**IP アドレスを、実際にフレームを届けるために必要な MAC アドレスへ変換する**こと。ただし ARP はそれを、リンク上の全員への **broadcast** で行います。

この Lab では、次の解決の流れを観察します。

- 2つの IPv4 ノードが1本のリンクを共有する（`10.0.0.1` と `10.0.0.2`）
- ARP cache をクリアした状態で `node-a` が `node-b` に ping する
- `node-a` が「`10.0.0.2` は誰? `10.0.0.1` に教えて」という ARP request を `ff:ff:ff:ff:ff:ff` へ **broadcast** する
- `node-b` が「`10.0.0.2` は `aa:...:b2` だよ」という ARP reply を **unicast** で返す
- `node-a` の ARP table に `10.0.0.2 → MAC` が入る

最終的に、Lab 23（NDP）とこの比較表を自分で埋められるようになるのがゴールです。

| | ARP（この Lab, IPv4） | NDP（Lab 23, IPv6） |
|---|---|---|
| 「X は誰?」の送り先 | **broadcast**（全員） | solicited-node multicast（該当者だけ） |
| プロトコル | 独自の EtherType `0x0806` | ICMPv6 |
| request / reply | ARP request / reply | Neighbor Solicitation / Advertisement |
| cache | ARP table（`ip neigh`） | neighbor cache（`ip -6 neigh`） |

## この Lab で学べること

- IP アドレスだけではリンク上でフレームを配送できず、MAC が必要になる理由
- ARP が「broadcast request + unicast reply」で IP → MAC を解決する仕組み
- ARP request / reply が運ぶ中身（"who-has"、"is-at"）
- ARP cache がどこにあり（`ip neigh`）、なぜ存在するのか
- broadcast は単純だが、NDP の multicast より非効率になる理由

一方、この Lab では次は扱いません。

- Gratuitous ARP、ARP probe / announce（RFC 5227）、proxy ARP
- ARP spoofing / セキュリティ
- RARP や歴史的な BOOTP との関係

## RFC で読む場所

| RFC | 章 | 読むポイント |
|---|---|---|
| RFC 826 | 全体 | ARP のパケット形式と解決アルゴリズム（短い） |
| RFC 826 | "Packet format" | hardware / protocol type、op（1=request, 2=reply） |
| RFC 1122 | 2.3.2 | ARP cache の扱い（ホスト要件） |

## 実験の全体像

IPv4 を付けた2ノードを1本のリンクで繋ぎます。

```text
node-a 10.0.0.1/24 ==== eth1/eth1 ==== node-b 10.0.0.2/24
```

node-a の ARP cache をクリアしてから ping すると、ARP による解決が走ります。

```mermaid
sequenceDiagram
  participant A as node-a (10.0.0.1)
  participant BC as broadcast<br/>ff:ff:ff:ff:ff:ff
  participant B as node-b (10.0.0.2)

  Note over A: cache cleared; wants 10.0.0.2's MAC
  A->>BC: ARP request "who has 10.0.0.2? tell 10.0.0.1"
  Note over B: that's me
  B->>A: ARP reply "10.0.0.2 is-at aa:...:b2" (unicast)
  Note over A: ARP table: 10.0.0.2 -> aa:...:b2
```

:::message
`10.0.0.0/24` はローカル閉域です。外部のインターネットには一切広告されません。
:::

## 必要なもの

推奨環境:

- Linux / WSL2 / Linux VM
- Docker
- containerlab

使用イメージ:

- `nicolaka/netshoot:latest`（`ip`、`ping`、ARP をデコードできる `tcpdump` を同梱）

追加イメージは不要です。

## 実行手順

一発で回すなら、次のコマンドで deploy → verify → destroy まで実行できます。

```bash
./scripts/labctl.sh run arp-24
```

以下は手順を1ステップずつ追う場合です。

### 1. 作業ディレクトリへ移動する

```bash
cd protocol-lab/examples/arp-24
```

### 2. 起動する

```bash
sudo containerlab deploy -t arp-24.clab.yml
```

### 3. ARP cache をクリアして、解決を観察する

```bash
docker exec clab-arp-24-node-a ip neigh flush all
docker exec -d clab-arp-24-node-a tcpdump -i eth1 -n -e "arp"
docker exec clab-arp-24-node-a ping -c2 10.0.0.2
docker exec clab-arp-24-node-a pkill -INT tcpdump
docker exec clab-arp-24-node-a tcpdump -n -e -vv -r /tmp/arp.pcap
```

見るポイント:

```text
aa:...:e2 > ff:ff:ff:ff:ff:ff, ARP, Request who-has 10.0.0.2 tell 10.0.0.1
aa:...:b2 > aa:...:e2, ARP, Reply 10.0.0.2 is-at aa:...:b2
```

### 4. ARP table を見る

```bash
docker exec clab-arp-24-node-a ip neigh show dev eth1
```

```text
10.0.0.2 lladdr aa:c1:ab:97:55:b2 REACHABLE
```

## 期待される出力

- `ping 10.0.0.2` が成功する
- capture に、宛先 `ff:ff:ff:ff:ff:ff` の `Request who-has 10.0.0.2 tell 10.0.0.1` と、`Reply 10.0.0.2 is-at <MAC>` が出る
- `ip neigh` に `10.0.0.2 lladdr <MAC> REACHABLE` が入る

## なぜそう動くのか

同じリンク上でフレームを届けるには、宛先の **MAC アドレス** が必要です。IP アドレスは「どのホストか」を示しますが、Ethernet はフレームを MAC で配送するからです。この「IP → MAC」を、IPv4 では ARP が解決します。

- **broadcast request**: node-a は node-b の MAC を知りません。そこで宛先を `ff:ff:ff:ff:ff:ff`（broadcast）にして「`10.0.0.2` は誰? `10.0.0.1` に教えて」を全員に送ります。リンク上の全ホストがこれを受け取ります。
- **unicast reply**: 該当する node-b だけが「私です、MAC はこれ」と返します。request には送信者（node-a）の IP と MAC が入っているので、reply は node-a へ unicast できます（全員に返す必要はありません）。
- **ARP cache**: 得た「IP → MAC」を cache します（`ip neigh`）。以後の通信はこの cache を使い、毎回 broadcast はしません。エントリは古くなると再確認されます。
- **NDP との違い（Lab 23）**: 役割は完全に同じ（IP → MAC）。違いは「聞き方」です。ARP は broadcast でリンク上の全員を起こします。NDP は相手の solicited-node multicast だけに送るので、無関係なホストを起こしません。IPv6 が broadcast を廃して multicast に統一したのは、この効率（と設計の整理）のためです。

要点は、**Ethernet は MAC で配送するので、IP から MAC を引く仕組みが必要**だということ。IPv4 はそれを broadcast の ARP で、IPv6 は multicast の NDP で行います。

## 詰まりやすい点

- **IP だけで届くと思ってしまう**。リンク上の配送は MAC 単位。ARP でそれを引きます。
- **request も reply も broadcast だと思ってしまう**。request は broadcast、reply は unicast です。
- **ARP がルータ越えでも使えると思ってしまう**。ARP は同一リンク（L2）内だけ。別セグメントの相手には、gateway の MAC を ARP で引きます。
- **cache を忘れる**。一度引いたら cache されます。毎回は聞きません。
- **NDP と役割が違うと思ってしまう**。役割は同じ。手段（broadcast vs multicast、独自 EtherType vs ICMPv6）が違うだけです。

## 後片付け

```bash
sudo containerlab destroy -t arp-24.clab.yml --cleanup
```

:::message
`labctl.sh run arp-24` を使った場合は、スクリプトが最後に自動で destroy します。
:::

## 確認問題

1. 同じリンク上でフレームを届けるのに、IP アドレスのほかに何が要るか。なぜか。
2. ARP request と reply は、それぞれ broadcast か unicast か。なぜそうできるのか。
3. ARP request の "who-has" と "tell" は何を意味するか。
4. ARP cache には何が入るか。なぜ cache するのか。
5. 別セグメント（ルータ越え）の相手に送るとき、ARP は誰の MAC を引くか。
6. ARP（IPv4）と NDP（IPv6）の違いを、「聞き方」の観点で説明せよ。

## 検証済み実行ログ（2026-07-07）

この Lab は実機で再現性を確認済みです。

実行環境:

- Ubuntu 26.04 LTS（kernel 7.0.0-27-generic, x86_64）
- Docker 29.1.3
- containerlab 0.77.0
- node-a / node-b: `nicolaka/netshoot:latest`（tcpdump 同梱）

`PATH="/tmp/pl-shim:$PATH" ./scripts/labctl.sh run arp-24` で deploy → verify → destroy を実行し、`verification.json` は `"status": "verified"` を返しました。

### ARP request（broadcast）→ reply（unicast）

```text
$ docker exec clab-arp-24-node-a tcpdump -n -e -vv -r arp.pcap
aa:c1:ab:10:4e:e2 > ff:ff:ff:ff:ff:ff, ethertype ARP (0x0806) ...
    Request who-has 10.0.0.2 tell 10.0.0.1, length 28
aa:c1:ab:97:55:b2 > aa:c1:ab:10:4e:e2, ethertype ARP (0x0806) ...
    Reply 10.0.0.2 is-at aa:c1:ab:97:55:b2, length 28
```

request は `ff:ff:ff:ff:ff:ff`（broadcast）へ、「`10.0.0.2` は誰? `10.0.0.1` に教えて」。該当する node-b だけが unicast で「`10.0.0.2` は `aa:c1:ab:97:55:b2`」と返しています。

### 解決後の ARP table

```text
$ docker exec clab-arp-24-node-a ip neigh show dev eth1
10.0.0.2 lladdr aa:c1:ab:97:55:b2 REACHABLE
```

`10.0.0.2` が MAC 付きで cache に入り `REACHABLE` になりました。以後はこの cache を使います。

Lab 23（NDP）と並べると、役割は同じ「IP → MAC」で、ARP は broadcast（全員）、NDP は solicited-node multicast（該当者だけ）という聞き方の違いがはっきり見えます。IPv6 が broadcast を廃した理由がここにあります。

## References

- [RFC 826: An Ethernet Address Resolution Protocol](https://www.rfc-editor.org/rfc/rfc826)
- [RFC 1122: Requirements for Internet Hosts — Communication Layers](https://www.rfc-editor.org/rfc/rfc1122)
- [RFC 5227: IPv4 Address Conflict Detection](https://www.rfc-editor.org/rfc/rfc5227)
- [RFC 5737: IPv4 Address Blocks Reserved for Documentation](https://www.rfc-editor.org/rfc/rfc5737)

---

この記事は **Protocol Lab** シリーズの一本です。ほかの Lab（BGP、TCP、TLS、DNS、IPv6 NDP など）もすべて手を動かして学べる形で公開しています。

📚 シリーズ一覧・全教材はこちら 👉 https://github.com/pathvector-studio/protocol-lab

役に立ったら、リポジトリに ⭐ を付けてもらえると励みになります。次回は、この Lab で対比した **IPv6 側の応用（近隣キャッシュの挙動や重複アドレス検出まわり）** を、より踏み込んで扱う予定です。
