# web/ — loam.dev Website (Astro, statisch)

Die Promo- und Doku-Website für **loam.dev**: das Tool vorstellen, die Funktionen
(Codebase-Intelligence + Anti-AI-Slop) und die Differenzierer (Ratchet-Gate,
LLM-Slop mit Cache, der interaktive HTML-Report) zeigen, und den Einstieg
(`dart pub global activate loam`) liefern.

## Stack

- **[Astro](https://astro.build) (latest, v6)** — reines Static-Site-Generation
  (`output: 'static'`, kein Adapter, kein Server).
- **Cloudflare Pages** (Free-Tier, Projekt `loam`, Domain `getloam.dev`), das **aus der
  Quelle baut** — `dist/` wird nicht eingecheckt (siehe `.gitignore`).
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

## Deployment

- **Host:** Cloudflare Pages, Projekt `loam` (`loam-3e3.pages.dev`, Custom-Domain `getloam.dev`).
- **Automatisch:** `.github/workflows/deploy-web.yml` baut bei jedem Push auf `main`, der `web/`
  berührt, frisch aus der Quelle und deployt als Production (`wrangler pages deploy`). Secrets
  `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` liegen als GitHub-Repo-Secrets.
- **Manuell** (Notfall, aus `web/`): `npm run build && npx wrangler pages deploy dist --project-name=loam --branch=main`.

## Offene Punkte

- Eingebetteter Beispiel-Report (das self-contained `loam-report.html` aus PRD §9) als
  Live-Showcase der Toggle-/Fix-Prompt-UX.
