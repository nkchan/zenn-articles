---
title: "BGP の最小単位「1 つの prefix 広告」を containerlab + FRR で動かして RFC 4271 の言葉で読む"
emoji: "🔀"
type: "tech"
topics:
  - "bgp"
  - "ネットワーク"
  - "rfc"
  - "containerlab"
published: false
---

## はじめに

BGP を「なんとなく知っている」から「人に説明できる」に変えるには、
できるだけ小さく動かして、実機の出力を RFC の言葉に対応させるのが一番の近道だと思っています。

この記事は、私が運用している [Protocol Lab](https://github.com/pathvector-studio/protocol-lab) の **BGP Lab 01** を、Zenn 記事として書き直したものです。
想定読者は次のような方:

- ネットワーク技術者で、BGP の動作を一度自分で動かして見ておきたい
- Rust や Go でルーティング関連のコードを触っている人
- RFC 4271 を読み始めたが、用語と挙動の対応がふわっとしている

ゴールは 1 行で:

> `203.0.113.0/24 via 10.0.0.1, AS_PATH 65001, ORIGIN IGP` を RFC 4271 の言葉で読めるようになる

これだけです。withdraw も RPKI も iBGP もまだ扱いません。広告 1 本だけ。

## 実験の全体像

2 台の仮想ルータを立てて、片方から 1 本だけ prefix を広告します。

```
AS65001 / r1                         AS65002 / r2
10.0.0.1/30  ----------------------  10.0.0.2/30

r1 advertises:
  203.0.113.0/24

r2 learns:
  prefix:   203.0.113.0/24
  next hop: 10.0.0.1
  as path:  65001
  origin:   IGP
```

`203.0.113.0/24` は [RFC 5737](https://datatracker.ietf.org/doc/html/rfc5737) の documentation prefix。
外部に広告すべきでない範囲なので、Lab の中だけで使っても誰にも迷惑をかけません。

実装は [containerlab](https://containerlab.dev/) と [FRRouting](https://frrouting.org/) を使います。`containerlab deploy` 1 コマンドで eBGP セッション込みのトポロジが立ち上がります。

## 必要なもの

- Linux マシン (私は Ubuntu 24.04 + Docker 29.4 で確認)
- Docker (`docker` グループに自分のユーザーを入れる)
- `containerlab` 0.75 以上

containerlab は Linux netns を直接触るので、Linux 専用です。
macOS で動かしたい場合は Lima や Multipass の上に Ubuntu を載せてください。
私の手元では nkchan-desktop-1 (Ubuntu 24.04) で実機検証しました。

ちなみに containerlab は **sudo なしで動きます** — `docker` グループに所属していれば。
ハマりどころなので明記しておきます。

## トポロジファイル (`bgp-01.clab.yml`)

```yaml
name: bgp-01
topology:
  nodes:
    r1:
      kind: linux
      image: frrouting/frr:latest
      binds:
        - r1/daemons:/etc/frr/daemons
        - r1/frr.conf:/etc/frr/frr.conf
        - r1/vtysh.conf:/etc/frr/vtysh.conf
    r2:
      kind: linux
      image: frrouting/frr:latest
      binds:
        - r2/daemons:/etc/frr/daemons
        - r2/frr.conf:/etc/frr/frr.conf
        - r2/vtysh.conf:/etc/frr/vtysh.conf
  links:
    - endpoints: ["r1:eth1", "r2:eth1"]
```

各ルータの `frr.conf` は eBGP セッション + 1 prefix 広告だけ書いてあります (r1 側だけ抜粋):

```text
router bgp 65001
 bgp router-id 1.1.1.1
 neighbor 10.0.0.2 remote-as 65002
 address-family ipv4 unicast
  network 203.0.113.0/24
  neighbor 10.0.0.2 activate
 exit-address-family
```

完全なファイルは [Protocol Lab レポジトリ](https://github.com/pathvector-studio/protocol-lab/tree/main/examples/bgp-01) にあります。

## 動かす

```bash
cd examples/bgp-01
containerlab deploy -t bgp-01.clab.yml
```

10-20 秒で 2 コンテナが立ち上がり、BGP セッションが open します。

## 観測する

### r1 から見たセッション

```text
$ docker exec clab-bgp-01-r1 vtysh -c "show ip bgp summary"

IPv4 Unicast Summary (VRF default):
BGP router identifier 1.1.1.1, local AS number 65001 vrf-id 0
BGP table version 1
RIB entries 1, using 192 bytes of memory
Peers 1, using 717 KiB of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt
10.0.0.2        4      65002         5         6        0    0    0 00:00:39            0        1
```

`PfxSnt 1` は r1 が r2 に対して 1 個の prefix (= 203.0.113.0/24) を広告していることを示します。
`State/PfxRcd 0` は r1 が r2 から何も受け取っていないこと。
このセッションは r1 → r2 の片方向広告だけです。

### r2 から見た route

```text
$ docker exec clab-bgp-01-r2 vtysh -c "show ip bgp"

   Network          Next Hop            Metric LocPrf Weight Path
*> 203.0.113.0/24   10.0.0.1                 0             0 65001 i
```

行頭の `*>` は valid + best。
`i` (一番右) は ORIGIN が IGP であることを示します。
`Path: 65001` が AS_PATH です。

### 詳細

```text
$ docker exec clab-bgp-01-r2 vtysh -c "show ip bgp 203.0.113.0/24"

BGP routing table entry for 203.0.113.0/24, version 1
Paths: (1 available, best #1, table default)
  Advertised to non peer-group peers:
  10.0.0.1
  65001
    10.0.0.1 from 10.0.0.1 (1.1.1.1)
      Origin IGP, metric 0, valid, external, best (First path received)
```

`Origin IGP, metric 0, valid, external, best` の 1 行に必要な情報が揃っています。

## RFC 4271 の言葉に対応させる

最初に立てたゴール:

> `203.0.113.0/24 via 10.0.0.1, AS_PATH 65001, ORIGIN IGP`

これを RFC 4271 の用語に置き換えます。

| RFC 4271 用語 | この Lab での実機表示 | 章 |
|---|---|---|
| NLRI (Network Layer Reachability Information) | `Network: 203.0.113.0/24` | §3.1, §4.3 |
| NEXT_HOP (mandatory path attribute) | `Next Hop: 10.0.0.1` | §5.1.3 |
| AS_PATH (mandatory path attribute) | `Path: 65001` | §5.1.2 |
| ORIGIN (mandatory path attribute) | `Origin IGP` (または行末の `i`) | §5.1.1 |

「route とは prefix と path attributes の組」(§3.1) という抽象的な定義が、
実機の 1 行 (`*> 203.0.113.0/24 10.0.0.1 ... 65001 i`) と直接対応していることが分かれば、
このラボはほぼ終わりです。

`UPDATE` メッセージで NLRI と path attributes が運ばれていく (§4.3) のも、
これで「ああ、あの 1 行を生成しているメッセージのことか」と腑に落ちます。

## Cleanup

```bash
containerlab destroy -t bgp-01.clab.yml --cleanup
```

netns・bridge・hosts エントリを全部後始末してくれます。

## ここまでできたら次にやること

- **Lab 02 (withdraw)**: 同じ route を `network` から外してみる → r2 が withdraw を受け取り、route table から消える流れを観測する
- **Lab 03 (競合 origin)**: AS_PATH の同じ prefix を別 AS から流す → どっちが best になるかと、それを判定する RFC 4271 §9.1 (Decision Process) を読む
- **RFC 4271 §1.1**: ここで出てきた用語 (Autonomous System / EBGP / IBGP / NLRI / Route) の正式な定義を一度通しで読む
- **Protocol Lab の full ページ**: 同じ Lab 01 の長尺版を [pathvector.dev/notes/bgp-01-full.html](https://pathvector.dev/notes/bgp-01-full.html) で公開しています。containerlab YAML や検証済み実行ログも全部載せてあります

## おわりに

私は PathVector Studio という名前で、ネットワークプロトコルを「読む / 動かす / 観察する」を 1 セットでまとめる小さな lab を作っています。
位置付けは **independent network protocol lab** で、教材はすべて無料公開です。

BGP は手強そうに見えますが、こうやって 1 つの広告から始めれば、RFC とコンソール出力の往復だけで十分追えます。
気が向いたら次の Lab も書きます。

---

Lab 本体: <https://github.com/pathvector-studio/protocol-lab/blob/main/labs/bgp-01-as-prefix-announcement.md>
Lab の HTML 版 (検証ログ含む): <https://pathvector.dev/notes/bgp-01-full.html>
