---
title: "ネットワークプロトコル学習ロードマップ — 42本のハンズオンと151本のコードリーディング、どこから歩く？"
emoji: "🗺️"
type: "tech"
topics: ["network", "protocol", "roadmap", "python", "containerlab"]
published: true
---

「ネットワークを学びたい」と思ったとき、いちばん難しいのは**順番**です。TCP/IPの本は分厚く、RFCは無限にあり、資格教材は暗記に寄りがち。この記事は、筆者が公開しているフリー教材2コース——手を動かす入門編 **Protocol Lab**（42 Lab）と、プロトコルをコードとして読む中級編 **Protocol in Code**（23トラック / 151セッション）——を素材に、**目的別の歩き方**をまとめたロードマップです。

- 入門編（ハンズオン）: https://github.com/pathvector-studio/protocol-lab
- 中級編（コードリーディング）: https://github.com/pathvector-studio/protocol-in-code

:::message
どちらも無料で、各リポジトリに置いてあります。この記事はその「地図」だけを切り出したものです。
:::

## 2コースの分担

学び方の型が違います。

| | Protocol Lab（入門） | Protocol in Code（中級） |
|---|---|---|
| 型 | RFCを少し読む → containerlabで動かす → パケットを観察 → 自分の言葉で説明 | 問い（Core Question）→ 30〜200行のPythonを読む → walkthroughを実行 → コードで答え合わせ |
| 1回分 | 40〜60分のLab | 30〜45分のセッション |
| 例 | BGPルータ2台で経路広告を流し、tcpdumpでUPDATEを見る | BGPのbest path選択を「順番に並んだif文」として読む |

**先にLabで動かし、気になったプロトコルを中級編でコードとして読む**のが基本の導線です。逆走も有効で、コードを読んでからLabを動かすと「頭の中のモデルが実パケットで裏取りできる」体験になります。

## まず迷ったら: 最初の12本

Protocol Lab の Lab 01〜12 は設計された導入シーケンスです。

BGP（経路はどう広がるか）→ RPKI（その経路は正当か）→ DNS（名前はどう引けるか）→ TCP（届くとはどういうことか）→ TLS（誰と話しているか）→ HTTP → QUIC → 最後に「1つのWebリクエストを全レイヤー縦断で追う」総集編。

週末に2本ずつで約6週間。ここまでで「ネットワークの全体像を、動かした経験つきで」持てます。

## ジャンルマップ

そこから先は番号順ではなく、ジャンルで選ぶのがおすすめです。両コースはほぼ同じジャンル構成になっています。

- **経路制御** — Lab: BGP/RPKI/OSPF/BFD/anycast/ECMP… → Code: bgp(15) → ospf(12) → rip(6) → rpki(5)
- **名前と信頼** — Lab: DNS/DNSSEC/DoT・DoH/DANE → Code: dns(8) → dnssec(5) → tls(9)
- **トランスポート** — Lab: TCP/輻輳制御/PMTUD/QoS → Code: tcp(11) → tcp2(6) → qos(5)
- **Webの配管** — Lab: TLS/HTTP/QUIC/LB → Code: http-quic(10) → lb(6)
- **ローカルセグメント** — Lab: DHCP/ARP/NDP/VLAN/IGMP → Code: arp(4) → stp(5) → igmp(4)
- **アドレスと到達性** — Lab: NAT/DNAT/traceroute → Code: dhcp(6) → nat(6) → ice(5) → icmp(5)
- **時刻と生死** — Code: ntp(4) → ha(4)（VRRP+BFD）
- **基礎と総括** — Code: parser(5)（バイト列の読み方そのもの）、meta(5)（後述）

## 目的別ルート（中級編）

### Webエンジニア: `fetch()` とサーバの間の全部

dns → tcp → tls → http-quic → lb → tcp2 → meta（55セッション）。終わると「遅いリクエスト」を名前解決・ハンドシェイク・HoLブロッキング・LBの選択・TIME_WAITの山まで分解して説明できます。

### インフラ/ネットワークエンジニア

parser → arp → dhcp → icmp → bgp → ospf → rip → rpki → stp → ha → meta（72セッション）。各トラックは対応するLabのcontainerlab演習と対で進めると効きます。

### セキュリティ志向

parser → tls → dnssec → rpki → arp → nat → ice → meta（44セッション）。縦糸は「**署名されているものと、ただ信じられているものの区別**」。DNSSECのINSECURE、RPKIのNOT_FOUND、ARPの無認証キャッシュ——「ダメ」に2種類ある設計が繰り返し出てきます。

### SRE/運用

tcp → tcp2 → lb → qos → ntp → ha → icmp → nat → igmp → meta（56セッション）。縦糸は「**沈黙は障害である**」——BFDの150msからTCP keepaliveの2時間まで、同じ推論が5桁違う時間スケールで現れます。

## どのルートでも最後は「Same Shape」

中級編の最終トラック **Same Shape, Different Protocol** は、コース全体が繰り返してきたコード構造を正面から扱う総括です。期限付きdict（DNSキャッシュ＝TLSチケット＝DHCPリース＝NATのconntrack）、比較関数による選出（BGP best path＝OSPF DR＝VRRP）、三値の判定、沈黙＝障害——そして22個の「toy loop」がぜんぶ同じ骨格だったこと。

**プロトコルを22個学んだつもりが、実は1つのプログラムを22回学んでいた**——ここまで歩いた人だけが笑える締めです。

## 始め方

```bash
# 入門編（要: Docker + containerlab）
git clone https://github.com/pathvector-studio/protocol-lab
# → labs/bgp-01-as-prefix-announcement.md から

# 中級編（要: Python 3.10+ のみ）
git clone https://github.com/pathvector-studio/protocol-in-code
PYTHONPATH=src python3 examples/dns/session_04_walkthrough.py
# → LEARNING_PATHS.md で自分のルートを選ぶ
```

各コースの詳細な対応表（Lab XX ↔ トラックYY）とルート定義は、リポジトリ内の `LEARNING_PATHS.md` にあります。この記事はその要約版です。

---

**Protocol Lab / Protocol in Code について**

どちらもフリー教材シリーズです。役に立ったらリポジトリの ⭐️ をお願いします。個々のLab・セッションの記事も順次公開しています。
