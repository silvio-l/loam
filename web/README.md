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
- **`@astrojs/sitemap`** — dokumentierte Ausnahme zur „keine Integrations"-Leitplanke:
  der Sitemap-Generator produziert deterministischen Build-Output (statisches XML),
  ist kein Runtime-Service und hat keine Drittanbieter-Call-Seite (kein Quota-Risiko).
  Alle anderen Integrations bleiben verboten.

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
| `src/layouts/Layout.astro` | Single Source des Chrome: Brand-Tokens, hreflang-Alternates, Versions-Chip, Footer-Links, self-hosted Spline Sans Mono. |
| `src/pages/index.astro` | Startseite EN (`/`) — Hero, Install, GitHub-Stars-CTA. |
| `src/pages/how-it-works.astro` | Pipeline-Erklärung EN (`/how-it-works`). |
| `src/pages/rules.astro` | Rule-Katalog EN (`/rules`). |
| `src/pages/privacy.astro` | Datenschutzerklärung EN (`/privacy`). |
| `src/pages/de/index.astro` | Startseite DE (`/de/`). |
| `src/pages/de/how-it-works.astro` | Pipeline-Erklärung DE (`/de/how-it-works`). |
| `src/pages/de/rules.astro` | Rule-Katalog DE (`/de/rules`). |
| `src/pages/de/privacy.astro` | Datenschutzerklärung DE (`/de/privacy`). |
| `src/pages/developer-guide.astro` | Developer & Tool Guide EN (`/developer-guide`) — rendert `docs/developer-guide.md`. |
| `src/pages/de/developer-guide.astro` | Developer & Tool Guide DE (`/de/developer-guide`) — gleicher Inhalt, DE-Hinweis. |
| `src/content.config.ts` | Content-Layer-Loader: liest `docs/developer-guide.md` direkt aus `../docs` (Single-Source, keine Kopie). |
| `src/i18n/` | Übersetzungsstrings (`ui.ts`) und Hilfsfunktionen (`utils.ts`, inkl. `hreflangAlternates`). |
| `src/components/` | Astro-Komponenten (z. B. `LanguageSwitcher.astro`, `GitHubStars.astro`, `RuleCard.astro`, `GuideArticle.astro`). |
| `public/` | Statische Assets, die 1:1 unter `/` ausgeliefert werden (Wortmarke, Icon, Favicon, OG-Image, `robots.txt`). |
| `astro.config.mjs` | `site: https://getloam.dev`, `output: 'static'`, `@astrojs/sitemap` mit i18n-Konfiguration. |
| `dist/` | Build-Output (gitignored). |

### Routen (10 Seiten)

| EN | DE | Inhalt |
|---|---|---|
| `/` | `/de/` | Startseite |
| `/how-it-works` | `/de/how-it-works` | Pipeline-Erklärung |
| `/rules` | `/de/rules` | Rule-Katalog |
| `/privacy` | `/de/privacy` | Datenschutz |
| `/developer-guide` | `/de/developer-guide` | Developer & Tool Guide (aus `docs/` gerendert) |

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
