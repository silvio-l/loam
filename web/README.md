# web/ — loam.dev Website (Astro, statisch)

Die Promo- und Doku-Website für **loam.dev**: das Tool vorstellen, die Funktionen
(Codebase-Intelligence + Anti-AI-Slop) und die Differenzierer (Ratchet-Gate,
LLM-Slop mit Cache, der interaktive HTML-Report) zeigen, und den Einstieg
(`dart pub global activate loam`) liefern.

## Stack

- **[Astro](https://astro.build) (latest, v6)** — reines Static-Site-Generation
  (`output: 'static'`, kein Adapter, kein Server).
- **Free-Tier-Hosting** (Cloudflare Pages / GitHub Pages), das **aus der Quelle baut** —
  `dist/` wird nicht eingecheckt (siehe `.gitignore`).
- Keine Integrations, keine Runtime-Abhängigkeiten: eine einzelne Seite, Brand-Tokens
  inline, Schrift via Google Fonts.

## Entwickeln

```bash
cd web
npm install
npm run dev      # lokaler Dev-Server (HMR)
npm run build    # Produktions-Build nach dist/
npm run preview  # gebautes dist/ lokal servieren
```

## Struktur

| Pfad | Zweck |
|---|---|
| `src/pages/index.astro` | Die Startseite (volles HTML-Dokument, Single Source des Markups). |
| `public/` | Statische Assets, die 1:1 unter `/` ausgeliefert werden (Wortmarke, Icon, Favicon, OG-Image). |
| `astro.config.mjs` | `site: https://getloam.dev`, `output: 'static'`. |
| `dist/` | Build-Output (gitignored). |

## Leitplanken

- **Statisch & Free-Tier.** Kein Server, keine bezifferbare Quota-Last (siehe
  Free-Tier-Disziplin in der globalen `CLAUDE.md`).
- **Naming:** Produktname überall **loam.dev**; `loam` nur als CLI-Befehl in Code-Snippets.
  **Web-Domain ist `getloam.dev`** (loam.dev selbst ist Premium/vergeben) — der Name bleibt
  loam.dev, die URL ist getloam.dev.
- **Brand-Tokens** stammen aus `assets/brand/tokens.json` (Single Source); die Werte sind
  in `src/pages/index.astro` gespiegelt und werden von `tool/docs-attest.sh check` erzwungen.
- **Kein Anti-Vokabular** (siehe `CONTEXT.md`) in der Web-Quelle — ebenfalls von der QS geprüft.

## Offene Punkte

- Eingebetteter Beispiel-Report (das self-contained `loam-report.html` aus PRD §9) als
  Live-Showcase der Toggle-/Fix-Prompt-UX.
- Hosting-Ziel final festzurren (Cloudflare Pages vs. GitHub Pages); Domain festgelegt: **`getloam.dev`**.
