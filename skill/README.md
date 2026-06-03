# skill/ — Claude-Skill/Plugin für loam.dev (Gerüst)

> Status: **Gerüst / geplant.** Noch kein Inhalt — dieses README hält Scope und
> Leitplanken fest, bis der Skill als eigenes Arbeitspaket gebaut wird.

## Zweck

Ein CLI-Tool wird von einem KI-Agenten am besten genutzt, wenn ein passender
**Claude-Skill/Plugin** den sauberen Pfad vorgibt. Dieser Skill kapselt die
`loam`-CLI, damit ein Agent loam.dev korrekt aufruft und die Ergebnisse
weiterverarbeitet — statt sich die Bedienung jedes Mal neu herzuleiten.

## Geplanter Ablauf (Skizze)

1. **Aufruf:** der Skill ruft `loam scan` / `loam gate` / `loam slop` mit
   `--format json` (bzw. `sarif`) auf — der maschinenlesbare Pfad aus PRD §9.
2. **Konsum:** Findings werden aus dem JSON-Output geparst (Agent-Pfad, kein Browser).
3. **Handlung:** der Agent priorisiert/erklärt Findings und fixt sie gezielt — analog
   zu dem Fix-Prompt, den der HTML-Report für Menschen baut, nur direkt im Agenten.
4. **Gate-Disziplin:** respektiert Baseline/Ratchet; schlägt keine Massen-Refactors
   an Altlasten vor.

## Leitplanken

- **Naming:** Produktname **loam.dev**; `loam` nur als CLI-Befehl.
- **Maschinen-Pfad zuerst:** der Skill nutzt `json`/`sarif`, nicht den HTML-Report
  (der ist der Mensch-Pfad).
- **Reproduzierbar:** nutzt dieselben deterministischen Gate-Schwellen wie die CLI.

## Offene Punkte (vor dem Bau zu entscheiden)

- Skill vs. vollständiges Plugin (mit Commands) — Distributionsform.
- Welche Subcommands der Skill kapselt (Minimal: `scan` + `gate`).
- Verhältnis zum interaktiven HTML-Report (Agent nutzt JSON, Mensch nutzt HTML).
