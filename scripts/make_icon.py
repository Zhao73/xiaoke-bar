"""生成 App 图标：暖色渐变圆角方块 + 像素小克。输出 Resources/AppIcon.icns"""
import os, subprocess, shutil
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024
BODY, LIGHT, DARK, EYE = (217,119,87), (235,148,117), (189,97,69), (31,26,23)

def clawd_pixels():
    px = []
    for y in range(0, 8):
        for x in range(2, 14):
            px.append((x, y, LIGHT if (y == 0 and x < 13) else (DARK if y == 7 else BODY)))
    for y in (2, 3):  # 双手举起，开心
        px += [(0, y, BODY), (1, y, BODY), (14, y, BODY), (15, y, BODY)]
    for x in (3, 5, 10, 12):
        px += [(x, 8, DARK), (x, 9, DARK)]
    for ex in (4, 11):
        px += [(ex, 2, EYE), (ex, 3, EYE)]
    return px

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# 背景：圆角方块，上浅下深的奶油→杏色渐变
bg = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(bg)
for y in range(S):
    t = y / S
    c = (int(255 - 18 * t), int(246 - 40 * t), int(236 - 58 * t), 255)
    d.line([(0, y), (S, y)], fill=c)
mask = Image.new("L", (S, S), 0)
m = 100
ImageDraw.Draw(mask).rounded_rectangle([m, m, S - m, S - m], radius=185, fill=255)
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([m, m + 14, S - m, S - m + 14], radius=185, fill=(120, 60, 30, 90))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
img.paste(bg, (0, 0), mask)

p = 40  # 每个像素 40px，16x10 → 640x400
ox, oy = (S - 16 * p) // 2, (S - 10 * p) // 2 + 30
dd = ImageDraw.Draw(img)
dd.ellipse([ox + 2 * p, oy + 10 * p - 10, ox + 14 * p, oy + 10 * p + 26], fill=(150, 80, 50, 60))
for x, y, c in clawd_pixels():
    dd.rectangle([ox + x * p, oy + y * p, ox + (x + 1) * p - 1, oy + (y + 1) * p - 1], fill=c + (255,))

out = os.path.join(ROOT, "Resources")
iconset = os.path.join(out, "AppIcon.iconset")
shutil.rmtree(iconset, ignore_errors=True)
os.makedirs(iconset)
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = size * scale
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        img.resize((px, px), Image.LANCZOS if px > 64 else Image.NEAREST).save(os.path.join(iconset, name))
img.save(os.path.join(out, "AppIcon-1024.png"))
subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(out, "AppIcon.icns")], check=True)
shutil.rmtree(iconset)
print("ok")
