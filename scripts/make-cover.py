#!/usr/bin/env python3
"""Zenn本のカバー画像(500x700)を生成する。

protocol-in-code シリーズ全23トラック分を同じ意匠で量産するためのテンプレート。
トラックごとに変わるのは「大見出しの記号(TCP など)」「サブタイトル」「アクセント色」
の3つだけで、レイアウトは固定する。

  ./scripts/make-cover.py TCP "動くおもちゃで読み解く11のしくみ" \
      --out books/protocol-in-code-tcp/cover.png

Zennの一覧では縮小表示されるため、記号を大きく取り文字数を絞る方針。
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont

W, H = 500, 700

BG = (13, 17, 28)
FG = (237, 242, 250)
MUTED = (128, 141, 166)
RULE = (36, 44, 62)

SANS = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
SANS_R = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# トラックごとのアクセント色。未登録のトラックは既定色にフォールバックする。
ACCENTS = {
    "TCP": (86, 176, 255),
    "DNS": (120, 208, 160),
    "TLS": (240, 176, 96),
    "BGP": (200, 144, 248),
}
DEFAULT_ACCENT = (86, 176, 255)


def font(path, size):
    return ImageFont.truetype(path, size)


def text_w(draw, s, f):
    return draw.textbbox((0, 0), s, font=f)[2]


def fit(draw, s, path, target_w, start, floor=10):
    """target_w に収まる最大のフォントサイズを返す。"""
    size = start
    while size > floor and text_w(draw, s, font(path, size)) > target_w:
        size -= 2
    return font(path, size)


def tokens(s):
    """CJKは1文字ずつ、ASCII英数の連なりは1トークンとして扱う。

    素朴に1文字ずつ折ると "10のしくみ" が "1" と "0のしくみ" に割れるため。
    """
    out, buf = [], ""
    for ch in s:
        if ch.isascii() and ch.isalnum():
            buf += ch
        else:
            if buf:
                out.append(buf)
                buf = ""
            out.append(ch)
    if buf:
        out.append(buf)
    return out


def wrap(draw, s, f, max_w):
    """CJK想定の折り返し。空白が無くても詰めて折る。"""
    lines, cur = [], ""
    for tok in tokens(s):
        if not cur or text_w(draw, cur + tok, f) <= max_w:
            cur += tok
        else:
            lines.append(cur)
            cur = tok
    if cur:
        lines.append(cur)
    return lines


def build(symbol, subtitle, series, tagline, note, accent):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # 左端のアクセントバー。シリーズの識別色。
    d.rectangle([0, 0, 8, H], fill=accent)

    pad = 46
    inner = W - pad * 2

    # 上部: シリーズ名
    f_series = font(SANS, 19)
    d.text((pad, 60), series, font=f_series, fill=accent)
    d.line([pad, 96, W - pad, 96], fill=RULE, width=1)

    # 「コードで学ぶ」→「TCP」の順に読ませる。記号が主役なので直上に置く。
    f_main = fit(d, tagline, SANS, inner, 40)
    d.text((pad, 158), tagline, font=f_main, fill=FG)

    # 記号を最大サイズで。カバーの主役。
    # bbox の y オフセットを引いて、描画位置ではなく字面の上端を揃える。
    f_sym = fit(d, symbol, MONO, inner, 200)
    bbox = d.textbbox((0, 0), symbol, font=f_sym)
    sym_top = 240
    sym_x = pad + (inner - (bbox[2] - bbox[0])) // 2 - bbox[0]
    d.text((sym_x, sym_top - bbox[1]), symbol, font=f_sym, fill=FG)

    # サブタイトル(折り返しあり)
    f_sub = font(SANS_R, 22)
    y = sym_top + (bbox[3] - bbox[1]) + 52
    for line in wrap(d, subtitle, f_sub, inner):
        d.text((pad, y), line, font=f_sub, fill=MUTED)
        y += 34

    # 販売情報。有料本なので試し読み範囲をカバー上で明示する。
    if note:
        d.text((pad, y + 18), note, font=font(SANS_R, 18), fill=accent)

    # 下部: 帯
    d.line([pad, H - 116, W - pad, H - 116], fill=RULE, width=1)
    f_foot = font(SANS_R, 18)
    d.text((pad, H - 96), "Python / 標準ライブラリだけで書く", font=f_foot, fill=MUTED)
    f_brand = font(SANS, 18)
    d.text((pad, H - 64), "pathvector", font=f_brand, fill=accent)

    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("symbol", help="大見出しの記号 (例: TCP)")
    ap.add_argument("subtitle", help="サブタイトル")
    ap.add_argument("--tagline", default="コードで学ぶ")
    ap.add_argument("--series", default="PROTOCOL IN CODE")
    ap.add_argument("--note", default="", help="カバー下部に出す販売情報 (例: 全12章 / 試し読み2章)")
    ap.add_argument("--accent", help="RRGGBB 形式。省略時はトラック既定色")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    if a.accent:
        h = a.accent.lstrip("#")
        accent = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    else:
        accent = ACCENTS.get(a.symbol.upper(), DEFAULT_ACCENT)

    img = build(a.symbol, a.subtitle, a.series, a.tagline, a.note, accent)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    img.save(a.out)
    print(f"{a.out} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
