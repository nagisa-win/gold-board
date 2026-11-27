#!/usr/bin/env python3
"""生成应用图标：暗色玻璃面板 + 悬浮胶囊 + 金色走势与按钮点。

输出 docs/images/appicon.png（源图）与 src/Resources/AppIcon.icns（打包用）。
依赖：Pillow；icns 由系统 sips + iconutil 生成。
"""
import math
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SS = 2048                     # 渲染超采样尺寸
OUT = 1024                    # 最终源图尺寸
GOLD_HI = (250, 224, 168)
GOLD = (226, 175, 96)
GOLD_LO = (176, 126, 52)
ROOT = Path(__file__).resolve().parents[1]


def radial_bg(size, center=(0.46, 0.24), radius=1.1):
    """中心偏亮的石墨底，四周压暗，形成聚光感。"""
    img = Image.new("RGB", (size, size))
    px = img.load()
    cx, cy = center[0] * size, center[1] * size
    maxd = radius * size
    inner, outer = (56, 59, 64), (10, 11, 12)
    for y in range(size):
        for x in range(size):
            t = min(1.0, math.hypot(x - cx, y - cy) / maxd) ** 1.6
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
    return img.convert("RGBA")


def rounded_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def glass(size, box, radius, top, bottom, rim_alpha, rim_width=6):
    """玻璃面：竖向渐变 + 圆角描边，避免用叠加矩形造成接缝。"""
    h = box[3] - box[1]
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    grad = grad.resize((box[2] - box[0], h)).convert("RGBA")
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer.paste(grad, (box[0], box[1]), rounded_mask(size, box, radius).crop(box))
    if rim_alpha:
        ImageDraw.Draw(layer).rounded_rectangle(box, radius=radius,
                                                outline=(255, 255, 255, rim_alpha), width=rim_width)
    return layer


def shadow(size, box, radius, alpha, blur, offset):
    """投影只往下偏，减少卡片上方的糊边。"""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        (box[0], box[1] + offset, box[2], box[3] + offset), radius=radius, fill=(0, 0, 0, alpha))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def glow_line(size, pts, width, color, blur):
    line = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(line).line(pts, fill=color, width=width, joint="curve")
    for p in (pts[0], pts[-1]):
        ImageDraw.Draw(line).ellipse((p[0] - width / 2, p[1] - width / 2,
                                      p[0] + width / 2, p[1] + width / 2), fill=color)
    return Image.alpha_composite(line.filter(ImageFilter.GaussianBlur(blur)), line)


def gold_button(size, box):
    """金色按钮点：实心金 + 顶部镜面高光 + 底部暗边。"""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse(box, fill=GOLD + (255,))
    w = box[2] - box[0]
    spec = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(spec).ellipse((box[0] + w * 0.16, box[1] + w * 0.10,
                                  box[2] - w * 0.26, box[1] + w * 0.40),
                                 fill=(255, 255, 255, 160))
    layer = Image.alpha_composite(layer, spec.filter(ImageFilter.GaussianBlur(w * 0.09)))
    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(rim).ellipse((box[0] + w * 0.10, box[3] - w * 0.32,
                                 box[2] - w * 0.10, box[3] - w * 0.05),
                                fill=GOLD_LO + (170,))
    return Image.alpha_composite(layer, rim.filter(ImageFilter.GaussianBlur(w * 0.07)))


def build():
    img = radial_bg(SS)

    # 后层：暗色玻璃面板
    card = (300, 430, 1750, 1520)
    img = Image.alpha_composite(img, shadow(SS, card, 250, 120, 62, 70))
    img = Image.alpha_composite(img, glass(SS, card, 250, (58, 62, 68), (30, 33, 37), 54))
    # 面板内的功能暗示（弱化走势）
    img = Image.alpha_composite(img, glow_line(
        SS, [(430, 1400), (660, 1348), (860, 1376), (1080, 1280), (1300, 1306), (1490, 1226)],
        12, (255, 255, 255, 26), 12))

    # 前层：悬浮胶囊
    cap = (380, 800, 1820, 1240)
    img = Image.alpha_composite(img, shadow(SS, cap, 220, 175, 46, 46))
    img = Image.alpha_composite(img, glass(SS, cap, 220, (48, 52, 58), (26, 28, 32), 96))
    # 顶部金色细边，强调「浮起来的边缘」
    hair = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    ImageDraw.Draw(hair).rounded_rectangle((cap[0] + 70, cap[1] + 12, cap[2] - 70, cap[1] + 20),
                                           radius=4, fill=GOLD_HI + (80,))
    img = Image.alpha_composite(img, hair.filter(ImageFilter.GaussianBlur(5)))

    img = Image.alpha_composite(img, glow_line(
        SS, [(540, 1046), (760, 992), (940, 1020), (1130, 936), (1300, 962), (1470, 900)], 28,
        GOLD_HI + (240,), 10))
    img = Image.alpha_composite(img, gold_button(SS, (1620, 936, 1752, 1068)))

    img.putalpha(rounded_mask(SS, (0, 0, SS - 1, SS - 1), 470))
    return img.resize((OUT, OUT), Image.LANCZOS)


def write_icns(png_path, icns_path):
    """sips 出各档尺寸 + iconutil 打包成 icns。"""
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size in (16, 32, 64, 128, 256, 512):
            for scale in (1, 2):
                px = size * scale
                name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
                subprocess.run(["sips", "-z", str(px), str(px), str(png_path),
                                "--out", str(iconset / name)],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns_path)], check=True)


if __name__ == "__main__":
    icon = build()
    png = ROOT / "docs/images/appicon.png"
    icns = ROOT / "src/Resources/AppIcon.icns"
    icon.save(png)
    write_icns(png, icns)
    print(f"wrote {png.relative_to(ROOT)} 和 {icns.relative_to(ROOT)}")
