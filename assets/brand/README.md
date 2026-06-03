# loam.dev — Corporate Design

**Eine Quelle, kein Drift.** Alle vom User sichtbaren Marken-Elemente (Logo,
Wortmarke, Farben, Schrift) werden aus **`tokens.json`** + zwei Vektor-Bausteinen
generiert und überall identisch verwendet — README, PNG, SVG, Terminal, Website.
Abweichungen sind durch die QS (`tool/docs-attest.sh check` → `brand-tokens`)
mechanisch verboten.

## Farb-Tokens (`tokens.json`)

| Token | Hex | Verwendung |
|---|---|---|
| `green` | `#88C840` | Trieb, `.dev`, Akzent |
| `soil` | `#564F47` | Boden-Schichten (sichtbar auf hell **und** dunkel) |
| `ink` | `#ECEAE3` | „loam", Text auf dunklem Grund |
| `bg` | `#101014` | dunkler Canvas (Lockups, Website) |
| `dim` | `#8D8A7E` | Sekundärtext |

**Keine Per-Oberflächen-Abweichung.** Frühere Drift-Werte (`#282420`, `#6A635A`,
`#7A7064`, `#F2F2F2`, `#ECE9E1`) sind Anti-Vokabular und werden von der QS in
Brand-Quellen + Website abgelehnt.

## Schrift

**Wortmarke: Spline Sans Mono** (SemiBold/`wght 600`), rundlich. Die Wortmarke
wird **aus der Schrift zu Outlines** erzeugt (`wordmark_from_font.py`) → font-freie
Pfade, überall identisch, kein Web-Font-Risiko. Auf der Website ist Spline Sans
Mono auch die UI-/Body-Schrift (Google Fonts).

## Logo-Aufbau

Mark = Trieb (grün) über drei Boden-Schichten (`soil`). Wortmarke = `loam`(ink)
+ `.dev`(green). Mark stammt aus dem freigegebenen Draft (potrace-Vektor),
eingefärbt mit den Tokens.

## Assets (alle generiert)

| Datei | Quelle |
|---|---|
| `icon-mark.png` / `_svg/icon-mark.svg` | `build.py` (Mark, transparent) |
| `icon-mono-white.png` / `_svg/icon-mono-white.svg` | `build.py` (einfarbig weiß) |
| `_svg/wordmark.svg` | `wordmark_from_font.py` (Spline → Outline) |
| `lockup-horizontal-dark.png` / `lockup-stacked-dark.png` | `build.py` (Mark + Wortmarke, Canvas `bg`) |
| `terminal-banner.png` · `ascii-banner.sh/.txt` | `_ascii/gen.py` (Halbblock-Pixel-Art) |
| `web/loam-lockup.png`, `web/icon-mark.svg`, `web/wordmark.svg`, `web/favicon.png` | von `build.py` nach `web/` kopiert (Website = exakt dieselben Dateien) |

## Neu generieren

Voraussetzungen: `rsvg-convert`, `Pillow`, `potrace` (nur für den Mark-Trace),
`fonttools` (venv, für die Wortmarke).

```bash
cd assets/brand
# 1) Wortmarke aus der Schrift (einmalig venv: python3 -m venv .venv && .venv/bin/pip install fonttools)
<venv>/bin/python _svg/wordmark_from_font.py
# 2) Icon, Mono, Lockups, web/-Kopien
python3 _svg/build.py
# 3) Terminal-Banner + ASCII
python3 _ascii/gen.py
```

`_svg/_mask_*.pbm` / `_svg/_trace_*.svg` sind die Mark-Zwischenstufen (potrace).

## ASCII / Terminal-Banner

Farbige Halbblock-Pixel-Art aus `icon-mark.svg` + `wordmark.svg`, Farben pro Zelle
auf die Tokens quantisiert. `ascii-banner.sh [big|compact|mini]` (Truecolor;
`NO_COLOR`/Pipe → Plain-Fallback).
