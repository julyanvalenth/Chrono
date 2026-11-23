"""Render the Chrono mark (lib/widgets/chrono_mark.dart) to the PNGs used for
the launcher icon and splash screen.

    python tool/make_brand_assets.py

Then regenerate the platform files:
    dart run flutter_launcher_icons
    dart run flutter_native_splash:create
"""
from pathlib import Path

from PIL import Image, ImageDraw

BG = (0x12, 0x11, 0x16, 255)     # C.bg
INK = (0xED, 0xEB, 0xF2, 255)    # C.ink   (clock face)
LIME = (0xC8, 0xF1, 0x69, 255)   # C.lime  (first quarter)
HOLE_RATIO = 0.25                # hole diameter / mark diameter (favicon: 6 of 24)
SS = 4                           # supersampling for smooth edges

OUT = Path(__file__).resolve().parent.parent / 'assets' / 'branding'


def mark(canvas: int, diameter_ratio: float, background=None) -> Image.Image:
    """Square image of `canvas` px with the mark centred, `diameter_ratio` of the canvas wide."""
    size = canvas * SS
    im = Image.new('RGBA', (size, size), background or (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    dia = size * diameter_ratio
    x0 = y0 = (size - dia) / 2
    box = [x0, y0, x0 + dia, y0 + dia]
    d.ellipse(box, fill=INK)
    d.pieslice(box, start=-90, end=0, fill=LIME)          # 12 o'clock → 3 o'clock
    hole = dia * HOLE_RATIO
    h0 = (size - hole) / 2
    d.ellipse([h0, h0, h0 + hole, h0 + hole], fill=BG)
    return im.resize((canvas, canvas), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = {
        # Full icon (iOS, web, legacy Android): dark square, mark fills ~62%.
        'app_icon.png': mark(1024, 0.62, BG),
        # Android adaptive icon foreground. flutter_launcher_icons insets it by 16%, so the mark ends up
        # ~37% of the icon, about 60% of the circle launchers show after masking.
        'app_icon_foreground.png': mark(1024, 0.54),
        # Splash before Android 12 / iOS / web: just the mark, shown at 1/4 size (4x asset) → 112 dp.
        'splash_logo.png': mark(448, 1.0),
        # Android 12+ splash icon: 960 px canvas, visible circle is the inner 640 px.
        'splash_logo_android12.png': mark(960, 0.5),
    }
    for name, im in files.items():
        im.save(OUT / name)
        print('wrote', OUT / name)


if __name__ == '__main__':
    main()
