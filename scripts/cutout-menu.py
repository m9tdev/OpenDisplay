#!/usr/bin/env python3
"""Cut a menu out of a screenshot, with a transparent background and a soft shadow.

    cutout-menu.py SOURCE DEST SCALE DARK

SOURCE is a capture of the screen area around the menu: 40 pt to the left and right of the menu, 30 pt above it,
and 40 pt below it, over a plain backdrop (see make-screenshots.sh). The menu is glass, so it must be captured over
the backdrop to look right; this script then removes the backdrop. DEST gets the margins of a system screenshot of
a menu: 23 pt at the sides, 19 pt at the top, and 21 pt at the bottom. SCALE is the backing scale (2 on Retina).
DARK is 1 for a dark menu (a stronger shadow).

Needs Pillow: pip3 install pillow
"""
import sys

from PIL import Image, ImageDraw, ImageFilter

source, dest, scale, dark = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4] == "1"
pt = lambda value: round(value * scale)

image = Image.open(source).convert("RGBA")
width, height = image.size
# The menu frame in the capture, with 1 px more on each side for the outline of the menu.
left, top = pt(40) - 1, pt(30) - 1
right, bottom = width - pt(40) + 1, height - pt(40) + 1

# A smooth mask with the menu's rounded corners (10 pt): drawn 4 times larger, then scaled down.
big = Image.new("L", (width * 4, height * 4), 0)
ImageDraw.Draw(big).rounded_rectangle((left * 4, top * 4, right * 4 - 1, bottom * 4 - 1), radius=pt(10) * 4, fill=255)
mask = big.resize((width, height), Image.LANCZOS)

# A soft shadow like the system menu shadow: a bit lower than the menu, blurred.
shadow = Image.new("L", (width, height), 0)
shadow.paste(mask.point(lambda v: int(v * (0.45 if dark else 0.25))), (0, pt(2)))
shadow = shadow.filter(ImageFilter.GaussianBlur(pt(4.5)))

out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
out.putalpha(shadow)
image.putalpha(mask)
out = Image.alpha_composite(out, image)
out = out.crop((left - pt(23), top - pt(19), right + pt(23), bottom + pt(21)))
out.save(dest)
