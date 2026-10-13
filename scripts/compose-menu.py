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

from PIL import Image

window_path, area_path, dest, scale = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

window = Image.open(window_path).convert("RGBA")
area = Image.open(area_path).convert("RGBA")

# The menu in the window capture: its opaque pixels. (The shadow around it is partly transparent.)
alpha = window.split()[3]
opaque = alpha.point(lambda a: 255 if a >= 250 else 0)
left, top, right, bottom = opaque.getbbox()

# The same menu in the area capture: 40 x 30 pt from its top left corner.
x, y = round(40 * scale), round(30 * scale)
inside = area.crop((x, y, x + right - left, y + bottom - top))

# Replace only the opaque pixels, so the system's rounded corners, outline, and shadow stay.
window.paste(inside, (left, top), opaque.crop((left, top, right, bottom)))
window.save(dest)
