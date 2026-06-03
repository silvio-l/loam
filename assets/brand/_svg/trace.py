#!/usr/bin/env python3
"""Schritt 1 der Logo-Pipeline: den freigegebenen KI-Draft vektorisieren.

Baut aus _ai-drafts/lockup-horizontal-dark.png vier Farb-Masken (Trieb, Boden,
"loam", ".dev") und tracet sie mit potrace zu _trace_<name>.svg. Danach
erzeugt build.py die finalen Assets. Idempotent: erzeugt Masken jedes Mal neu.
"""
import os, subprocess
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "_ai-drafts", "lockup-horizontal-dark.png")
XSPLIT = 520  # links Mark, rechts Wortmarke

im = Image.open(SRC).convert("RGB"); W, H = im.size; px = im.load()

def green(r, g, b): return g > 120 and g > r + 30 and g > b + 30
def soil(r, g, b):  return 25 < r < 95 and 20 < g < 88 and 16 < b < 82 \
                           and abs(r - g) < 24 and abs(g - b) < 24
def ink(r, g, b):   return r > 150 and g > 150 and b > 150

mk = {k: Image.new("L", (W, H), 255) for k in ("sprout", "soil", "loam", "dev")}
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        if green(r, g, b):
            (mk["sprout"] if x < XSPLIT else mk["dev"]).putpixel((x, y), 0)
        elif soil(r, g, b) and x < XSPLIT:
            mk["soil"].putpixel((x, y), 0)
        elif ink(r, g, b) and x >= XSPLIT:
            mk["loam"].putpixel((x, y), 0)

# Trieb leicht entrauschen (duenne Trace-Schlitze/Faeden weg), Form bleibt.
mk["sprout"] = mk["sprout"].filter(ImageFilter.MedianFilter(5))

for k, m in mk.items():
    m = m.point(lambda p: 0 if p < 128 else 255)
    p = os.path.join(HERE, f"_mask_{k}.pbm"); m.save(p)
    subprocess.run(["potrace", "-s", "-o", os.path.join(HERE, f"_trace_{k}.svg"),
                    "--turdsize", "6", "--alphamax", "1", p],
                   check=True, stderr=subprocess.DEVNULL)
    print("traced", k)
