"""Export the approved Predict P. design to platform icon sizes.
Usage: python scripts/build-app-icons.py /path/to/approved-logo.png
"""
import sys
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
source = Image.open(sys.argv[1]).convert('RGB')
assert source.width == source.height
icons = root / 'icons'
for size in (16, 32, 180, 192, 512):
    source.resize((size, size), Image.Resampling.LANCZOS).save(icons / f'predict-v2-{size}.png', optimize=True)
source.resize((256, 256), Image.Resampling.LANCZOS).save(icons / 'predict-v2.ico', sizes=[(16,16),(32,32),(48,48)])
# Android can crop maskable icons to a circle: keep the design in its safe zone.
maskable = Image.new('RGB', (512, 512), '#101010')
maskable.paste(source.resize((440, 440), Image.Resampling.LANCZOS), (36, 36))
maskable.save(icons / 'predict-v2-maskable-512.png', optimize=True)
# Status-bar badges are monochrome alpha masks, not full-colour squares.
alpha = Image.new('L', source.size)
alpha.putdata([max(0, min(255, int((min(g,b)-r-15)*255/170))) for r,g,b in source.getdata()])
badge = Image.new('RGBA', source.size, 'white')
badge.putalpha(alpha)
badge.resize((96,96), Image.Resampling.LANCZOS).save(icons / 'predict-v2-badge-96.png', optimize=True)
