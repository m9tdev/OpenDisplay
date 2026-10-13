#!/usr/bin/env python3
"""Make a menu screenshot with the system margins and shadow, and the right glass.

    compose-menu.py WINDOW AREA DEST SCALE

WINDOW is a window capture of the menu (screencapture -l): it has the system margins, shadow, and rounded corners,
with a transparent background. But the menu is glass, and a window capture has nothing behind the glass, so the
inside of the menu is gray.

AREA is a capture of the screen area around the same menu (40 pt to the left, 30 pt above it), over a plain
backdrop: there the glass looks right.

DEST gets WINDOW with the inside of the menu from AREA. SCALE is the backing scale (2 on Retina displays).

Needs Pillow: pip3 install pillow
"""
import sys

from PIL import Image, ImageChops, ImageFilter, ImageStat

window_path, area_path, dest, scale = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

window = Image.open(window_path).convert("RGBA")
area = Image.open(area_path).convert("RGBA")

# The menu in the window capture: its opaque pixels. (The shadow around it is partly transparent.)
alpha = window.split()[3]
opaque = alpha.point(lambda a: 255 if a >= 250 else 0)
left, top, right, bottom = opaque.getbbox()

# The same menu in the area capture: about 40 x 30 pt from its top left corner, but the exact position can be a few
# pixels off. The text and icons are the same in both captures (only the glass differs), so find the offset where
# their edges line up best.
width, height = right - left, bottom - top
edges = lambda image: image.convert("L").filter(ImageFilter.FIND_EDGES)
margin = round(16 * scale)  # Compare only the inside, away from the outline of the menu.
target = edges(window.crop((left, top, right, bottom))).crop((margin, margin, width - margin, height - margin))
area_edges = edges(area)
x0, y0 = round(40 * scale), round(30 * scale)
search = round(4 * scale)


def mismatch(dx, dy):
    x, y = x0 + dx, y0 + dy
    candidate = area_edges.crop((x + margin, y + margin, x + width - margin, y + height - margin))
    return sum(ImageStat.Stat(ImageChops.difference(target, candidate)).mean)


dx, dy = min(((dx, dy) for dx in range(-search, search + 1) for dy in range(-search, search + 1)), key=lambda d: mismatch(*d))
x, y = x0 + dx, y0 + dy
print(f"{dest}: menu found {dx:+d} x {dy:+d} px from the expected position", file=sys.stderr)
inside = area.crop((x, y, x + width, y + height))

# Replace only the opaque pixels, so the system's rounded corners, outline, and shadow stay.
window.paste(inside, (left, top), opaque.crop((left, top, right, bottom)))
window.save(dest)
