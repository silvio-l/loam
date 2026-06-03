#!/usr/bin/env python3
"""Single source of truth fuer das loam.dev-Logo.

Faithful-Vektorisierung des freigegebenen KI-Drafts
(_ai-drafts/lockup-horizontal-dark.png): Trieb, Boden, "loam" und ".dev" wurden
mit potrace je als eigene Maske vektorisiert. Aus DIESEN Pfaden werden alle
Varianten abgeleitet -> Mark ueberall pixel-identisch, font-frei, reproduzierbar.

Regenerieren:
  1) Masken+Trace erzeugen (siehe _svg/trace.sh)
  2) python3 build.py
"""
import os, re, glob

GREEN = "#88C840"; SOIL = "#282420"; BG = "#101014"; INK = "#F2F2F2"
HERE = os.path.dirname(os.path.abspath(__file__))
FLIP = 'translate(0.000000,1024.000000) scale(0.100000,-0.100000)'

def paths(name):
    """Alle <path>-Elemente eines potrace-SVG als Blob (fill entfernt)."""
    txt = open(os.path.join(HERE, f"_trace_{name}.svg")).read()
    ps = re.findall(r'<path\b[^>]*\bd="[^"]*"[^>]*/>', txt)
    ps = [re.sub(r'\sfill="[^"]*"', '', p) for p in ps]
    return "\n".join(ps)

def bbox(name, minsize=50):
    """Bounding-Box (Pixelkoord.) aus der Maske, ohne Streupixel."""
    from PIL import Image
    from collections import deque
    im = Image.open(os.path.join(HERE, f"_mask_{name}.pbm")).convert("L")
    w, h = im.size; px = im.load()
    seen = bytearray(w * h)
    xs0 = ys0 = 10**9; xs1 = ys1 = -1
    for y in range(h):
        for x in range(w):
            if px[x, y] == 0 and not seen[y * w + x]:
                q = deque([(x, y)]); seen[y * w + x] = 1; pts = []
                while q:
                    cx, cy = q.popleft(); pts.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and px[nx, ny] == 0 \
                                and not seen[ny * w + nx]:
                            seen[ny * w + nx] = 1; q.append((nx, ny))
                if len(pts) >= minsize:
                    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
                    xs0 = min(xs0, min(xs)); xs1 = max(xs1, max(xs))
                    ys0 = min(ys0, min(ys)); ys1 = max(ys1, max(ys))
    return (xs0, ys0, xs1, ys1)

def union(*bs):
    return (min(b[0] for b in bs), min(b[1] for b in bs),
            max(b[2] for b in bs), max(b[3] for b in bs))

P = {n: paths(n) for n in ("sprout", "soil", "loam", "dev")}
B = {n: bbox(n) for n in ("sprout", "soil", "loam", "dev")}
MARK = union(B["sprout"], B["soil"])
WORD = union(B["loam"], B["dev"])

def fill_group(items, tx=0.0, ty=0.0):
    """items: Liste (name, color). Optionaler Aussen-Translate in User-Units."""
    inner = "\n".join(
        f'<g fill="{c}"><g transform="{FLIP}">\n{P[n]}\n</g></g>' for n, c in items)
    if tx or ty:
        return f'<g transform="translate({tx:.2f},{ty:.2f})">\n{inner}\n</g>'
    return inner

def svg(vb, body, bg=None):
    x0, y0, w, h = vb
    rect = f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="{bg}"/>' if bg else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="{x0} {y0} {w} {h}">\n{rect}\n{body}\n</svg>\n')

def write(name, content):
    open(os.path.join(HERE, name), "w").write(content)
    print("wrote", name)

# --- 1) Icon-Mark (transparent, quadratisch) -------------------------------
mx0, my0, mx1, my1 = MARK
mcx, mcy = (mx0 + mx1) / 2, (my0 + my1) / 2
side = max(mx1 - mx0, my1 - my0) + 90          # 45px Rand
icon_vb = (mcx - side / 2, mcy - side / 2, side, side)
write("icon-mark.svg",
      svg(icon_vb, fill_group([("soil", SOIL), ("sprout", GREEN)])))

# --- 2) Monochrom weiss (transparent) --------------------------------------
write("icon-mono-white.svg",
      svg(icon_vb, fill_group([("soil", "#FFFFFF"), ("sprout", "#FFFFFF")])))

# --- 3) Lockup horizontal (1:1-Layout des Drafts, nur zugeschnitten) --------
ux0, uy0, ux1, uy1 = union(MARK, WORD)
pad = 70
h_vb = (ux0 - pad, uy0 - pad, (ux1 - ux0) + 2 * pad, (uy1 - uy0) + 2 * pad)
write("lockup-horizontal.svg",
      svg(h_vb,
          fill_group([("soil", SOIL), ("sprout", GREEN),
                      ("loam", INK), ("dev", GREEN)]),
          bg=BG))

# --- 4) Lockup gestapelt: Mark oben mittig, Wort darunter -------------------
wx0, wy0, wx1, wy1 = WORD
wcx, wcy = (wx0 + wx1) / 2, (wy0 + wy1) / 2
mark_w, mark_h = mx1 - mx0, my1 - my0
word_w, word_h = wx1 - wx0, wy1 - wy0
gap = 70; pad = 70
canvas_w = max(mark_w, word_w) + 2 * pad
target_cx = canvas_w / 2 + (h_vb[0])  # arbitrar; wir nutzen lokale coords unten
# Wir arbeiten in einem frischen, lokalen Koordinatenrahmen:
cw = max(mark_w, word_w) + 2 * pad
ch = pad + mark_h + gap + word_h + pad
mark_tx = (cw / 2 - mcx)            # Mark-Mitte -> Canvas-Mitte X
mark_ty = (pad + mark_h / 2 - mcy)  # Mark-Mitte -> oben
word_tx = (cw / 2 - wcx)
word_ty = (pad + mark_h + gap + word_h / 2 - wcy)
sbody = (fill_group([("soil", SOIL), ("sprout", GREEN)], mark_tx, mark_ty)
         + fill_group([("loam", INK), ("dev", GREEN)], word_tx, word_ty))
write("lockup-stacked.svg", svg((0, 0, cw, ch), sbody, bg=BG))

# --- 5) Wortmarke solo (transparent) — für Terminal-Banner-Rendering --------
wpad = 12
w_vb = (wx0 - wpad, wy0 - wpad, (wx1 - wx0) + 2 * wpad, (wy1 - wy0) + 2 * wpad)
write("wordmark.svg",
      svg(w_vb, fill_group([("loam", INK), ("dev", GREEN)])))

print("MARK bbox", MARK, " WORD bbox", WORD)
