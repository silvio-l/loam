#!/usr/bin/env python3
"""Single source of truth fuer das loam.dev-Logo — alles aus tokens.json.

Mark (Trieb + Boden) = potrace-Vektor des freigegebenen Drafts, eingefaerbt mit
den Marken-Tokens. Wortmarke = Spline-Sans-Mono-Outline (wordmark_from_font.py).
Aus beidem werden Icon, Mono und die Lockups generiert — EINE Quelle, kein Drift.

Pipeline:
  1) (einmalig) trace.py  -> _trace_*.svg / _mask_*.pbm  (Mark)
  2) wordmark_from_font.py -> wordmark.svg               (Wortmarke, braucht venv+fonttools)
  3) build.py             -> icon/mono SVG + PNG, Lockup-PNGs, web/loam-lockup.png
Braucht: rsvg-convert, Pillow.
"""
import os, re, json, subprocess
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
TOK = json.load(open(os.path.join(HERE, "..", "tokens.json")))
GREEN, SOIL, BG, INK = TOK["green"], TOK["soil"], TOK["bg"], TOK["ink"]
FLIP = 'translate(0.000000,1024.000000) scale(0.100000,-0.100000)'

def paths(name):
    txt = open(os.path.join(HERE, f"_trace_{name}.svg")).read()
    ps = re.findall(r'<path\b[^>]*\bd="[^"]*"[^>]*/>', txt)
    return "\n".join(re.sub(r'\sfill="[^"]*"', '', p) for p in ps)

def bbox(name, minsize=50):
    from collections import deque
    im = Image.open(os.path.join(HERE, f"_mask_{name}.pbm")).convert("L")
    w, h = im.size; px = im.load(); seen = bytearray(w * h)
    xs0 = ys0 = 10**9; xs1 = ys1 = -1
    for y in range(h):
        for x in range(w):
            if px[x, y] == 0 and not seen[y * w + x]:
                q = deque([(x, y)]); seen[y * w + x] = 1; pts = []
                while q:
                    cx, cy = q.popleft(); pts.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and px[nx, ny] == 0 and not seen[ny * w + nx]:
                            seen[ny * w + nx] = 1; q.append((nx, ny))
                if len(pts) >= minsize:
                    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
                    xs0, xs1 = min(xs0, min(xs)), max(xs1, max(xs))
                    ys0, ys1 = min(ys0, min(ys)), max(ys1, max(ys))
    return (xs0, ys0, xs1, ys1)

P = {n: paths(n) for n in ("sprout", "soil")}
B = {n: bbox(n) for n in ("sprout", "soil")}
MARK = (min(B["sprout"][0], B["soil"][0]), min(B["sprout"][1], B["soil"][1]),
        max(B["sprout"][2], B["soil"][2]), max(B["sprout"][3], B["soil"][3]))

def mark_group(soil_c, sprout_c):
    return (f'<g fill="{soil_c}"><g transform="{FLIP}">{P["soil"]}</g></g>'
            f'<g fill="{sprout_c}"><g transform="{FLIP}">{P["sprout"]}</g></g>')

def svg(vb, body, bg=None):
    x0, y0, w, h = vb
    rect = f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="{bg}"/>' if bg else ''
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="{x0} {y0} {w} {h}">\n{rect}\n{body}\n</svg>\n')

def write(name, content):
    open(os.path.join(HERE, name), "w").write(content); print("wrote", name)

# --- Icon (transparent, quadratisch) + Mono -------------------------------
mx0, my0, mx1, my1 = MARK
mcx, mcy = (mx0 + mx1) / 2, (my0 + my1) / 2
side = max(mx1 - mx0, my1 - my0) + 90
icon_vb = (mcx - side / 2, mcy - side / 2, side, side)
write("icon-mark.svg", svg(icon_vb, mark_group(SOIL, GREEN)))
write("icon-mono-white.svg", svg(icon_vb, mark_group("#FFFFFF", "#FFFFFF")))

# --- PNG-Rendering ---------------------------------------------------------
def rsvg(svg_path, out, h=None, w=None):
    arg = ["-h", str(h)] if h else ["-w", str(w)]
    subprocess.run(["rsvg-convert", *arg, svg_path, "-o", out], check=True)

def trimmed(path):
    im = Image.open(path).convert("RGBA"); return im.crop(im.split()[3].getbbox())

OUT = os.path.normpath(os.path.join(HERE, ".."))
rsvg(os.path.join(HERE, "icon-mark.svg"), os.path.join(OUT, "icon-mark.png"), w=1024)
rsvg(os.path.join(HERE, "icon-mono-white.svg"), os.path.join(OUT, "icon-mono-white.png"), w=1024)

# --- Lockups (Mark + Wortmarke) via Komposition ----------------------------
MARK_H = 520                          # Mark-Hoehe im Lockup (px)
WORD_H = round(MARK_H * 0.50)         # Wortmarken-(Glyphen-)Hoehe -> Balance
PAD, GAP = 90, 90
bgcol = tuple(int(BG[i:i+2], 16) for i in (1, 3, 5))

rsvg(os.path.join(HERE, "icon-mark.svg"), "/tmp/_mk.png", h=MARK_H + 200)
rsvg(os.path.join(HERE, "wordmark.svg"), "/tmp/_wm.png", h=WORD_H + 400)
mk = trimmed("/tmp/_mk.png"); wm = trimmed("/tmp/_wm.png")
# auf Zielhoehen skalieren
mk = mk.resize((round(mk.width * MARK_H / mk.height), MARK_H), Image.LANCZOS)
wm = wm.resize((round(wm.width * WORD_H / wm.height), WORD_H), Image.LANCZOS)

def compose(layout):
    if layout == "h":
        cw = PAD + mk.width + GAP + wm.width + PAD
        ch = PAD + max(mk.height, wm.height) + PAD
        canvas = Image.new("RGBA", (cw, ch), (*bgcol, 255))
        canvas.alpha_composite(mk, (PAD, (ch - mk.height) // 2))
        canvas.alpha_composite(wm, (PAD + mk.width + GAP, (ch - wm.height) // 2))
    else:  # stacked
        cw = PAD + max(mk.width, wm.width) + PAD
        ch = PAD + mk.height + GAP + wm.height + PAD
        canvas = Image.new("RGBA", (cw, ch), (*bgcol, 255))
        canvas.alpha_composite(mk, ((cw - mk.width) // 2, PAD))
        canvas.alpha_composite(wm, ((cw - wm.width) // 2, PAD + mk.height + GAP))
    return canvas.convert("RGB")

compose("h").save(os.path.join(OUT, "lockup-horizontal-dark.png"))
compose("v").save(os.path.join(OUT, "lockup-stacked-dark.png"))
print("wrote lockup-horizontal-dark.png, lockup-stacked-dark.png")

# Web nutzt dasselbe Lockup (pub.dev-README laedt es von getloam.dev)
import shutil
WEB = os.path.join(ROOT, "web")
shutil.copy(os.path.join(OUT, "lockup-horizontal-dark.png"),
            os.path.join(WEB, "loam-lockup.png"))
# Website bindet exakt dieselben generierten Vektoren ein -> kein Drift.
for f in ("icon-mark.svg", "wordmark.svg"):
    shutil.copy(os.path.join(HERE, f), os.path.join(WEB, f))
shutil.copy(os.path.join(OUT, "icon-mark.png"), os.path.join(WEB, "favicon.png"))
print("copied -> web/ (loam-lockup.png, icon-mark.svg, wordmark.svg, favicon.png)")
print("MARK bbox", MARK, "| soil", SOIL, "green", GREEN, "ink", INK)
