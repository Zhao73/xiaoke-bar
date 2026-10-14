#!/bin/bash
# 重新生成 README 用的截图、宠物动图和横幅（全部是演示数据，不读本机任何会话和账号）
# 用法：./scripts/readme-assets/make.sh     需要 ffmpeg、Python3 + Pillow、Google Chrome
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
OUT=$ROOT/docs/images
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

swift build -c release
for lang in en zh-Hans; do
  XIAOKE_DEMO=1 .build/release/XiaokeBar --snapshot "$TMP/$lang" -language "$lang" >/dev/null 2>&1
done

# 宠物动图：72 帧 12fps，像素风用最近邻缩放、不抖动
ffmpeg -loglevel error -y -framerate 12 -i "$TMP/en/frames/f%03d.png" \
  -vf "scale=iw/2:-1:flags=neighbor,split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];[b][p]paletteuse=dither=none" \
  -loop 0 "$OUT/pets.gif"

python3 - "$TMP" "$OUT" "$ROOT/scripts/readme-assets" <<'PY'
import sys, shutil
from PIL import Image
tmp, out, src = sys.argv[1:4]
tabs = ['0-quota', '1-sessions', '2-stats', '3-billing', '4-settings']

def squash(im, path):
    # 256 色调色板，体积约 1/4，肉眼几乎看不出
    im.convert('RGB').quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)

def combo(lang, look, name):
    ims = [Image.open(f'{tmp}/{lang}/{look}-{t}.png') for t in tabs]
    w, h = ims[0].size
    c = Image.new('RGB', (w * 5, h))
    for k, im in enumerate(ims):
        c.paste(im.convert('RGB'), (k * w, 0))
    c.thumbnail((3000, 3000))
    squash(c, f'{out}/{name}')

for t, name in zip(tabs, ['usage-dark', 'sessions', 'stats', 'billing', 'settings']):
    squash(Image.open(f'{tmp}/en/dark-{t}.png'), f'{out}/{name}.png')
squash(Image.open(f'{tmp}/en/light-0-quota.png'), f'{out}/usage-light.png')
squash(Image.open(f'{tmp}/en/pets-gallery.png'), f'{out}/pets-gallery.png')
combo('en', 'dark', 'overview-dark.png'); combo('en', 'light', 'overview-light.png'); combo('zh-Hans', 'dark', 'overview-zh.png')
for f in ['floating.png', 'floating-collapsed.png', 'band-erquan.png', 'band-saints.png']:
    shutil.copy(f'{tmp}/en/{f}', f'{out}/{f}')

# 横幅素材：面板截图 + 从动图第 30 帧里抠出四只宠物
hero = f'{tmp}/hero'; import os; os.makedirs(hero)
shutil.copy(f'{src}/hero.html', hero)
shutil.copy(f'{tmp}/en/dark-0-quota.png', f'{hero}/usage.png')
shutil.copy(f'{tmp}/en/dark-2-stats.png', f'{hero}/stats.png')
im = Image.open(f'{tmp}/en/frames/f030.png').convert('RGBA')
bg = im.getpixel((2, 2))
cw, ch = (im.width - 40) // 7, (im.height - 40) // 4   # 7 个动作 × 4 只宠物（2 倍图，四周各 20px 边距）
for r, c, n in [(0, 1, 'p-claude'), (1, 4, 'p-codex'), (2, 6, 'p-grok'), (3, 2, 'p-gemini')]:
    cell = im.crop((20 + c * cw, 20 + r * ch, 20 + (c + 1) * cw, 20 + (r + 1) * ch))
    px = cell.load()
    for i in range(cell.width):
        for j in range(cell.height):
            p = px[i, j]
            if abs(p[0] - bg[0]) + abs(p[1] - bg[1]) + abs(p[2] - bg[2]) < 6:
                px[i, j] = (0, 0, 0, 0)
    cell.crop(cell.getbbox()).save(f'{hero}/{n}.png')
PY

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
timeout 30 "$CHROME" --headless=new --disable-gpu --hide-scrollbars --user-data-dir="$TMP/chrome" \
  --force-device-scale-factor=2 --window-size=1600,820 --screenshot="$TMP/hero.png" "file://$TMP/hero/hero.html" >/dev/null 2>&1 || true
# 横幅不做调色板压缩：渐变标题会出色带
python3 -c "from PIL import Image; Image.open('$TMP/hero.png').convert('RGB').save('$OUT/hero.png', optimize=True)"
echo "已生成到 $OUT"
ls -la "$OUT"
