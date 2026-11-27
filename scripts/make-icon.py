#!/usr/bin/env python3
"""生成 app 图标：深色圆角底 + 金色「金」字 + 底部走势线。"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
FONT = "/Users/yanjunzhu/Library/Fonts/MapleMono-NF-CN-Bold.ttf"
GOLD_TOP = (246, 210, 138)
GOLD_BOTTOM = (206, 152, 58)


def squircle_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        draw.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


# 底：石墨渐变 + 顶部高光
base = gradient(S, (32, 36, 40), (14, 16, 18)).convert("RGBA")
highlight = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(highlight).ellipse((-S * 0.25, -S * 0.55, S * 1.25, S * 0.42), fill=(255, 255, 255, 26))
base = Image.alpha_composite(base, highlight.filter(ImageFilter.GaussianBlur(60)))

# 「金」字：垂直金色渐变
font = ImageFont.truetype(FONT, 560)
glyph = Image.new("L", (S, S), 0)
ImageDraw.Draw(glyph).text((S / 2, 448), "金", font=font, fill=255, anchor="mm")
gold = gradient(S, GOLD_TOP, GOLD_BOTTOM).convert("RGBA")
gold.putalpha(glyph)

# 字后柔光，避免纯平贴上去
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
glow.paste((246, 210, 138, 70), (0, 0), glyph.filter(ImageFilter.GaussianBlur(28)))
base = Image.alpha_composite(base, glow)

# 底部走势线：示意金价曲线
line = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(line)
pts = [(252, 806), (352, 786), (432, 800), (522, 756), (612, 772), (702, 726), (792, 736)]
d.line(pts, fill=(246, 210, 138, 200), width=24, joint="curve")

icon = Image.alpha_composite(base, gold)
icon = Image.alpha_composite(icon, line.filter(ImageFilter.GaussianBlur(1)))

# 内描边：模拟玻璃厚度
edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(edge).rounded_rectangle((6, 6, S - 7, S - 7), radius=225, outline=(255, 255, 255, 40), width=4)
icon = Image.alpha_composite(icon, edge)

icon.putalpha(squircle_mask(S, 225))
icon.save("docs/images/appicon.png")
print("wrote docs/images/appicon.png （再用 sips + iconutil 生成 src/Resources/AppIcon.icns）")
