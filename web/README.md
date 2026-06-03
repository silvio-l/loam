# web/ — loam.dev Website (Gerüst)

> Status: **Gerüst / geplant.** Noch kein Inhalt — dieses README hält Scope und
> Leitplanken fest, bis die Website als eigenes Arbeitspaket gebaut wird.

## Zweck

Die Promo- und Doku-Website für **loam.dev**: das Tool vorstellen, die Funktionen
(Codebase-Intelligence + Anti-AI-Slop) und die Differenzierer (Ratchet-Gate,
LLM-Slop mit Cache, der interaktive HTML-Report) zeigen, und den Einstieg
(`dart pub global activate loam`) liefern.

## Leitplanken

- **Statisch & Free-Tier.** Reines Static-Site-Hosting (z. B. Cloudflare Pages oder
  GitHub Pages) — kein Server, keine bezifferbare Quota-Last (siehe Free-Tier-Disziplin
  in der globalen `CLAUDE.md`). Konkrete Tech-Wahl ist noch offen.
- **Naming:** Produktname überall **loam.dev**; `loam` nur als CLI-Befehl in Code-Snippets.
- **Eine mögliche Killer-Demo:** ein eingebetteter Beispiel-Report (das self-contained
  `loam-report.html` aus PRD §9) als Live-Showcase der Toggle-/Fix-Prompt-UX.

## Offene Punkte (vor dem Bau zu entscheiden)

- Static-Site-Generator / Framework (oder Plain HTML).
- Hosting-Ziel (Cloudflare Pages vs. GitHub Pages) + Domain `loam.dev`.
- Verhältnis zur pub.dev-Package-Page (Doku-Single-Source vermeiden).
