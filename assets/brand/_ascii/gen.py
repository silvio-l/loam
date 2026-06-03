#!/usr/bin/env python3
"""loam.dev Terminal-Banner als farbige Pixel-Art aus dem echten Logo.

Technik wie GitHub Copilot CLI: Vektor-Logo rastern, in Terminal-Zellen sampeln.
Pro Zelle ein Halbblock '▀' (Vordergrund = oberer Pixel, Hintergrund = unterer
Pixel) -> 2 vertikale Pixel je Zelle, Truecolor. Farben werden pro Zelle auf
die Marken-Palette QUANTISIERT (Grün / Erd-Grau / Weiß / transparent) -> knackige
Kanten statt matschigem Antialiasing.

Ein Banner ist ein Gitter aus (oben, unten)-Farbzellen. Daraus werden ANSI
(fürs Terminal) und eine PNG-Vorschau identisch erzeugt:
  python3 gen.py            # schreibt ../ascii-banner.{txt,sh}
  python3 gen.py preview    # + PNG-Vorschauen nach /tmp/_loam_*.png

Voraussetzungen: rsvg-convert, Pillow.
"""
import os, sys, subprocess
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, ".."))
SVGDIR = os.path.join(OUT, "_svg")

import json as _json
_TOK = _json.load(open(os.path.join(HERE, "..", "tokens.json")))
def _rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
GREEN = _rgb(_TOK["green"])   # Trieb / .dev   (aus tokens.json)
SOIL  = _rgb(_TOK["soil"])    # Erde           (aus tokens.json)
INK   = _rgb(_TOK["ink"])     # loam           (aus tokens.json)
TERMBG = _rgb(_TOK["bg"])     # nur für PNG-Vorschau
ESC = "\x1b"; R = f"{ESC}[0m"
DIMSEQ = f"{ESC}[38;2;120;120;128m"
TAG = "codebase intelligence + anti-ai-slop"

def snap(r, g, b, a):
    if a < 110: return None
    if g > r + 18 and g > b + 18: return GREEN
    if r > 150 and g > 150 and b > 150: return INK
    return SOIL

def grid(svg, cols):
    """-> Liste von Zeilen; Zelle = (top_rgb|None, bot_rgb|None)."""
    subprocess.run(["rsvg-convert", "-w", "1100", os.path.join(SVGDIR, svg),
                    "-o", "/tmp/_g.png"], check=True)
    im = Image.open("/tmp/_g.png").convert("RGBA"); im = im.crop(im.split()[3].getbbox())
    w, h = im.size
    rows = max(1, round(cols * (h / w) / 2))
    g = im.resize((cols, rows * 2), Image.LANCZOS); p = g.load()
    out = []
    for r in range(rows):
        out.append([(snap(*p[c, 2 * r]), snap(*p[c, 2 * r + 1])) for c in range(cols)])
    return out

def width(gr): return max((len(r) for r in gr), default=0)

def hcenter(gr, w):
    out = []
    for row in gr:
        lead = (w - len(row)) // 2
        out.append([(None, None)] * lead + row + [(None, None)] * (w - len(row) - lead))
    return out

def vstack(grids, gap=1):
    w = max(width(g) for g in grids)
    grids = [hcenter(g, w) for g in grids]
    blank = [[(None, None)] * w]
    out = []
    for i, g in enumerate(grids):
        if i: out += blank * gap
        out += g
    return out

def vcenter(gr, h):
    w = width(gr); pad = (h - len(gr)) // 2
    blank = [(None, None)] * w
    return [blank] * pad + gr + [blank] * (h - len(gr) - pad)

def hstack(grids, gap=2):
    h = max(len(g) for g in grids)
    grids = [vcenter(g, h) for g in grids]
    out = []
    for r in range(h):
        row = []
        for i, g in enumerate(grids):
            if i: row += [(None, None)] * gap
            row += g[r]
        out.append(row)
    return out

# ---- Emitter ----------------------------------------------------------------
def cell_glyph(top, bot):
    if top and bot: return "▀", top, bot
    if top:         return "▀", top, None
    if bot:         return "▄", bot, None
    return " ", None, None

def fg(c): return f"{ESC}[38;2;{c[0]};{c[1]};{c[2]}m"
def bg(c): return f"{ESC}[48;2;{c[0]};{c[1]};{c[2]}m"

def to_ansi(gr):
    lines = []
    for row in gr:
        # trailing leere Zellen kürzen
        last = max((i for i, (t, b) in enumerate(row) if t or b), default=-1)
        s = ""; cur = None
        for i in range(last + 1):
            ch, f, b = cell_glyph(*row[i])
            spec = (f, b)
            if spec != cur:
                seq = ""
                if f: seq += fg(f)
                seq += bg(b) if b else f"{ESC}[49m"
                s += seq; cur = spec
            s += ch
        lines.append(s + R if last >= 0 else "")
    return lines

def to_png(gr, path, scale=12):
    h = len(gr); w = width(gr)
    img = Image.new("RGB", (w * scale, h * 2 * scale), TERMBG); px = img.load()
    for r, row in enumerate(gr):
        for c, (top, bot) in enumerate(row):
            for half, col in ((0, top), (1, bot)):
                if not col: continue
                x0 = c * scale; y0 = (r * 2 + half) * scale
                for yy in range(y0, y0 + scale):
                    for xx in range(x0, x0 + scale):
                        px[xx, yy] = col
    img.save(path)

# ---- Banner-Layouts ---------------------------------------------------------
def big():     return vstack([grid("icon-mark.svg", 32), grid("wordmark.svg", 60)], gap=1)
def compact():  return hstack([grid("icon-mark.svg", 12), grid("wordmark.svg", 52)], gap=3)

BIG, COMP = big(), compact()

def with_tag(lines, w):
    pad = max(0, (w - len(TAG)) // 2)
    return lines + ["", " " * pad + DIMSEQ + TAG + R]

big_c  = with_tag(to_ansi(BIG), width(BIG))
comp_c = to_ansi(COMP)
# mini: farbiger Einzeiler (Pixel-Art wäre zu klein zum Lesen)
mini_c = [f"{fg(GREEN)}▟▙{R} {fg(INK)}loam{fg(GREEN)}.dev{R}"]

FALLBACK = [
    r"  \ /   _                 _       ",
    r"  \|/  | | ___  __ _ _ __ | |_____",
    r"  [#]  | |/ _ \/ _` | '  \| / -_) ",
    r"  [#]  |_|\___/\__,_|_|_|_|_\___|  .dev",
    r"  [#]                              ",
    r"        " + TAG,
]

# Marketing-Asset (Root-README): farbiges Banner als PNG, aus denselben Tokens.
to_png(BIG, os.path.join(OUT, "terminal-banner.png"))
print("wrote terminal-banner.png")

if "preview" in sys.argv:
    to_png(BIG, "/tmp/_loam_big.png"); to_png(COMP, "/tmp/_loam_compact.png")
    print("PNG-Vorschauen: /tmp/_loam_{big,compact}.png")

# ---- .txt -------------------------------------------------------------------
struct = "\n".join("".join(c if (c:=("█" if (t or b) else " ")) else " "
                           for t, b in row) for row in BIG)
open(os.path.join(OUT, "ascii-banner.txt"), "w").write(
f"""loam.dev — Terminal-Banner (farbige Pixel-Art)
==============================================

Halbblock-Rasterung des echten Logos (Truecolor), Farben pro Zelle quantisiert
auf die Marken-Tokens (assets/brand/tokens.json). Technik wie GitHub Copilot CLI.
Die FARBIGE Fassung trägt die Form nur über Farbe und lässt sich nicht als
Plain-Text zeigen — live ansehen:

  bash assets/brand/ascii-banner.sh big       # auch: compact | mini

Struktur "big" (nur Belegung, ohne Farbe):

{struct}

Plain-Fallback (NO_COLOR / Pipe / nicht-TTY):

""" + "\n".join(FALLBACK) + "\n")

# ---- .sh --------------------------------------------------------------------
def block(lines): return "\n".join(lines)
sh = f"""#!/usr/bin/env bash
# loam.dev Terminal-Banner. Usage: ./ascii-banner.sh [big|compact|mini]
# Farbige Pixel-Art (Truecolor). NO_COLOR / nicht-TTY -> Plain-Fallback.
set -euo pipefail
size="${{1:-big}}"
if [ -n "${{NO_COLOR:-}}" ] || [ ! -t 1 ]; then
cat <<'EOF'
{block(FALLBACK)}
EOF
  exit 0
fi
case "$size" in
  big) cat <<'EOF'
{block(big_c)}
EOF
  ;;
  compact) cat <<'EOF'
{block(comp_c)}
EOF
  ;;
  mini) cat <<'EOF'
{block(mini_c)}
EOF
  ;;
  *) echo "usage: $0 [big|compact|mini]" >&2; exit 2 ;;
esac
"""
p = os.path.join(OUT, "ascii-banner.sh")
open(p, "w").write(sh); os.chmod(p, 0o755)
print("geschrieben: ascii-banner.txt, ascii-banner.sh")
