# loam.dev — Brand-Assets

Logo, Farben und ASCII-Banner für loam.dev. **Single Source of Truth sind
Vektorpfade** (SVG), nicht generierte Bilder — so ist das Mark in jedem Asset
pixel-identisch und reproduzierbar (vgl. Kern-Invariante *Reproduzierbarkeit*).
Generative Bildmodelle würfeln das Symbol bei jedem Lauf neu und sind für ein
Logo ungeeignet.

## Herkunft

Das Logo wurde einmalig per KI-Bild entworfen (`_ai-drafts/`), der freigegebene
Entwurf dann mit **potrace** zu sauberen Vektorpfaden **nachgezeichnet** (Trieb,
Boden, „loam", „.dev" je als eigene Maske). Alle ausgelieferten Assets werden
aus diesen Pfaden generiert.

## Motiv

Ein Trieb (zwei organische Blätter + Stiel) wächst aus drei gestapelten,
gerundeten Boden-Horizonten. Doppeldeutig: Boden = *loam*, die Schichten =
*Layer/Boundary* (was das Tool analysiert), der Spross = gesunder Code.
Wortmarke in gerundeter Monospace, `.dev` im Trieb-Grün.

## Farben

| Token | Hex | Verwendung |
|---|---|---|
| Grün (Trieb / `.dev`) | `#88C840` | Akzent, Blätter, Stiel |
| Erde (Boden) | `#282420` | Boden-Horizonte |
| Grund (dunkel) | `#101014` | Lockup-Hintergrund |
| Ink (Wortmarke) | `#F2F2F2` | „loam" auf dunklem Grund |

## Assets

| Datei | Zweck |
|---|---|
| `icon-mark.png` / `_svg/icon-mark.svg` | Icon-Mark, transparent, quadratisch — Favicon, pub.dev-Avatar, App-Icon |
| `icon-mono-white.png` / `_svg/icon-mono-white.svg` | Einfarbig weiß, transparent — dunkle Hintergründe |
| `lockup-horizontal-dark.png` / `_svg/lockup-horizontal.svg` | Haupt-Logo (Symbol + Wort), README-Header, Web-Navbar |
| `lockup-stacked-dark.png` / `_svg/lockup-stacked.svg` | Gestapelt — Website-Hero, quadratische Flächen |
| `terminal-banner.png` | PNG des farbigen Terminal-Banners (Pixel-Art) — für README/Web als „so sieht's im Terminal aus" |
| `ascii-banner.sh` / `ascii-banner.txt` | Farbiger Terminal-Banner (Big/Compact/Mini) + Plain-Fallback |

Die **SVGs sind komplett font-frei** (Schrift ist als Pfad vektorisiert) und
damit voll portabel — kein Font-Dependency beim Web-Einsatz.

## Neu generieren

Voraussetzungen: `potrace`, `librsvg` (`rsvg-convert`), Python mit `Pillow`.

```bash
cd assets/brand/_svg
python3 trace.py        # Schritt 1: Draft -> Masken -> potrace -> _trace_*.svg
python3 build.py        # Schritt 2: ein Mark -> alle Varianten als SVG
# Schritt 3: rastern (viewBox-treu, exakte Größe, Transparenz erhalten)
rsvg-convert -w 1024 icon-mark.svg        -o ../icon-mark.png
rsvg-convert -w 1024 icon-mono-white.svg  -o ../icon-mono-white.png
rsvg-convert -w 1600 lockup-horizontal.svg -o ../lockup-horizontal-dark.png
rsvg-convert -w 1100 lockup-stacked.svg    -o ../lockup-stacked-dark.png
```

`_svg/_mask_*.pbm` und `_svg/_trace_*.svg` sind Zwischenstufen; sie liegen für
Nachvollziehbarkeit bei und werden von `trace.py` neu erzeugt.

## Terminal-Banner (farbige Pixel-Art)

Der Banner ist **kein handgemaltes ASCII**, sondern eine farbige Pixel-Art-
Rasterung des echten Logos — dieselbe Technik wie die GitHub-Copilot-CLI:
Artwork rastern, in Terminal-Zellen sampeln. Pro Zelle ein **Halbblock `▀`**
mit Vordergrund = oberer Pixel, Hintergrund = unterer Pixel (2 vertikale Pixel
je Zelle), **Truecolor (24-bit)**. So bleibt der echte Trieb organisch und die
Schichten exakt wie im Logo.

Farben werden pro Zelle auf die Palette **quantisiert** (knackige Kanten statt
Antialiasing): Trieb/`.dev` = `#88C840`; Erde = Logo-Grau `#282420`, für
Terminal-Sichtbarkeit auf `#6A635A` aufgehellt (Grau-Familie, **kein Braun**);
`loam` weiß. Auch die Wortmarke ist Pixel-Art aus der echten Logo-Schrift
(`wordmark.svg`) — kein figlet.

Größen:
- **big** — gestapelt: Mark (32 Zellen) über Wortmarke (60), Tagline. Splash.
- **compact** — horizontal: kleines Mark + lesbare Wortmarke (~7 Zeilen, <80 Spalten).
- **mini** — farbiger Einzeiler.

- **`ascii-banner.sh [big|compact|mini]`** — farbige Ausgabe (Truecolor).
  Automatisch aus bei `NO_COLOR=1` / nicht-TTY / Pipe → **Plain-Fallback**.
  Live ansehen: `bash assets/brand/ascii-banner.sh big`
- **`ascii-banner.txt`** — Struktur-Referenz + Plain-Fallback (die farbige
  Fassung lässt sich nicht sinnvoll als Plain-Text zeigen).
- **`_ascii/gen.py [preview]`** — Generator (braucht `rsvg-convert`, `Pillow`);
  rendert Banner + `terminal-banner.png` neu aus den Vektor-Quellen.
