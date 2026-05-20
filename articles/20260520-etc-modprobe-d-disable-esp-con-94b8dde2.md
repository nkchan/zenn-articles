---
title: "/etc/modprobe.d/disable-esp.conf を作成してモジュールを無効化"
emoji: "🤖"
type: "tech"
topics:
  - "ai"
  - "network"
  - "linux"
  - "security"
published: false
---

echo "install esp4 /bin/true" > /etc/modprobe.d/disable-esp.conf
echo "install esp6 /bin/true" >> /etc/modprobe.d/disable-esp.conf
echo "install rxrpc /bin/true" >> /etc/modprobe.d/disable-esp.conf

# 適用を反映
rmmod esp4 esp6 rxrpc 2>/dev/null || true
```

また、攻撃の前提としてネットワーク環境のセットアップが必要となるケースが多いため、非特権ユーザーによる User Namespace の作成を制限することも多層防御（Defense in Depth）として有効です。

## 考察

今回のFragnesiaの発見は、エンジニアにとって非常に興味深い示唆を含んでいます。

第一に、「AIによる脆弱性ハンティング」が実用的なフェーズに入ったことです。興味深いことに、Fragnesiaは過去の脆弱性（Dirty Frag）の修正パッチが原因で意図せず「到達しやすくなった（Accidentally activated）」状態にあり、それをAIエージェントが即座に捕捉しました。人間のレビューアが見逃しやすい副作用的なリグレッションを、AIが網羅的かつ自律的に追跡できることを証明しています。Linus Torvalds氏らメンテナ陣も「AIによるジャンクレポートの氾濫」を警戒する一方で、こうした高品質な報告に対しては対応指針をアップデートせざるを得なくなっています。

第二に、XFRMやゼロコピー（`splice`等）に関連するサブシステムの複雑性です。パフォーマンスを極限まで引き出すためのインプレース処理やページキャッシュの共有機構は、エッジケースにおいて極めて危険な状態（Dirty COWの再来のような状態）を引き起こす爆弾を孕んでいます。我々エンジニアは、便利で高速なAPIの裏側にある「状態管理の破綻リスク」を常に意識し、不要な機能はコンテナホストレベルで積極的にDrop・Denylist化していく運用がますます重要になると言えます。

## 参考

- [The Hacker News: AI Agents Discover Critical Linux Kernel Vulnerability](https://thehackernews.com/)
- [Security Affairs: Fragnesia LPE Flaw in Linux Kernel](https://securityaffairs.com/)
- [TuxCare: Understanding CVE-2026-46300](https://tuxcare.com/)