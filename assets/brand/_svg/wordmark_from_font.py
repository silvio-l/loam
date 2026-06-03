#!/usr/bin/env python3
"""Reproduzierbare Wortmarke: 'loam.dev' aus Spline Sans Mono -> Outline-SVG.

Single source: aus der DEFINIERTEN Schrift werden font-freie Pfade erzeugt,
damit die Wortmarke in README/PNG/SVG/Web/Terminal IMMER identisch ist.
Braucht fonttools (venv). Aufruf: python wordmark_from_font.py
"""
import os, glob, json
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

HERE=os.path.dirname(os.path.abspath(__file__))
TOK=json.load(open(os.path.join(HERE,"..","tokens.json")))
FONT=glob.glob(os.path.expanduser("~/Library/Fonts/SplineSansMono[[]wght[]].ttf"))[0]
WEIGHT=TOK["font_wordmark_weight"]; TEXT="loam.dev"; SPLIT=4
INK=TOK["ink"]; GREEN=TOK["green"]

f=TTFont(FONT); instantiateVariableFont(f,{"wght":WEIGHT},inplace=True)
gs=f.getGlyphSet(); cmap=f.getBestCmap()
asc=f["OS/2"].sTypoAscender; desc=f["OS/2"].sTypoDescender
adv=f["hmtx"][cmap[ord("l")]][0]

def path_for(ch,xoff):
    pen=SVGPathPen(gs)
    gs[cmap[ord(ch)]].draw(TransformPen(pen,(1,0,0,-1,xoff,asc)))
    return pen.getCommands()

groups={INK:[],GREEN:[]}
for i,ch in enumerate(TEXT):
    groups[INK if i<SPLIT else GREEN].append(path_for(ch,i*adv))
W=len(TEXT)*adv; H=asc-desc
body="\n".join(f'<g fill="{c}"><path d="{" ".join(ps)}"/></g>' for c,ps in groups.items() if ps)
svg=(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
     f'viewBox="0 0 {W} {H}">\n{body}\n</svg>\n')
open(os.path.join(HERE,"wordmark.svg"),"w").write(svg)
print(f"wordmark.svg geschrieben — W={W} H={H} adv={adv} (Spline Sans Mono @wght{WEIGHT})")
