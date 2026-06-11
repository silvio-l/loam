# Changelog

## 0.1.6

- **New rule: `complexity-hotspots`.** Measures cyclomatic and cognitive
  complexity per executable over the resolved AST and flags hotspots that breach
  documented, conservative defaults (cyclomatic > 20 or cognitive > 30; a
  cyclomatic-only breach also requires cognitive > 5, so flat lookup tables and
  generated-style boilerplate stay quiet). Findings carry a stable fingerprint
  anchored on the qualified symbol name, so line shifts don't churn the baseline.
  Suppress individually with `// loam-ignore: complexity-hotspots – <reason>`.
- **New command: `loam health`.** A diagnostic aggregate view — Health-Score
  (0–100), Grade (A–F) and a descending hotspot table — rendered by its own
  terminal renderer. It always measures (independent of the `complexity-hotspots`
  rule toggle) and is a report, not a gate: exit 0 even on a low score, exit 64
  on a usage error.
- **New rule: `circular-dependencies`.** Detects import cycles across first-party
  Dart libraries (Tarjan strongly-connected components over the import graph);
  export-only re-exports are excluded so barrel files don't false-positive.
- **Positional project path.** `scan`, `gate`, `init` and `baseline` now accept
  the project root as a positional `[path]`; `-p`/`--project-root` overrides it.
- **Fewer false positives.** Flutter `gen-l10n` output is treated as generated
  and excluded from analysis.
- **Update notice (opt-out).** Prints a one-line stderr notice (at most once a
  day) when a newer release is on pub.dev; silence it with `--no-update-check`,
  the `LOAM_NO_UPDATE_CHECK` env var, or `update_check: false` in `loam.yaml`.
  CI is always silent.
- **HTML report shows a Health-Score badge.** When `loam scan` emits HTML, a
  Score + Grade badge is rendered in the report head via a sidecar; the other
  formats and the `ReportPayload` contract are unchanged.
- **`--format html` now writes a file and opens it.** Instead of streaming to
  stdout, the HTML report is written to `loam-report.html` (override with
  `--output <file>`) and opened in the default browser on interactive runs.
  Auto-open is suppressed for piped/redirected output and under CI; `--no-open`
  skips it explicitly. The other formats (`human`/`sarif`/`json`/`markdown`)
  still stream to stdout unchanged.
- **Redesigned HTML report.** Two-column layout with a sticky side panel that
  keeps the severity summary, the toolchain facts and the always-visible
  Fix-Prompt in view — no more scrolling to the page foot. Adds an inline brand
  mark, a terminal-styled masthead, a live search/filter across file, rule and
  message, and per-finding rule IDs that deep-link to the matching rule on
  getloam.dev. Footer and masthead link to the website, the repository and the
  sponsor page. The reporter stays a pure, byte-identical renderer.


## 0.1.4

- **Documentation release** (no functional changes). Adds an `example/` so the
  pub.dev package page renders a usage example, and documents the full public API
  surface (`Finding`, `Severity`, `Rule`, `ProjectLoader`, …). The
  `public_member_api_docs` lint now keeps public-API documentation complete.


## 0.1.3

- **`--format markdown`** is now available: a portable Markdown report alongside
  `human`, `sarif` and `json`.
- **`--format html`** is now available: a single self-contained, offline
  `loam-report.html` (inline CSS/JS, no server, no CDN). Browse findings by rule,
  severity and file; select findings and copy a deterministic, versioned
  (`prompt@ver`) fix-prompt for an AI coding agent. The report is a pure renderer —
  no thresholds, no LLM calls. Redirect stdout:
  `loam scan --format html > loam-report.html`.
- **User-driven suppression via `loam.yaml`.** A project-root `loam.yaml` now
  drives per-rule toggles (`rules:`) and path-based `ignore:` globs (project-
  relative). A disabled rule is not run at all and changes the `rulesetVersion`;
  glob-ignored files drop out of the audit entirely. Suppression acts before the
  baseline/gate and never fills the baseline or trips the gate.
- **Inline suppression `// loam-ignore: <ruleId> – reason`.** Suppress a single
  finding at its source on the same or immediately preceding line, via the
  analyzer comment model (not text regex). The reason is mandatory; only the named
  rule is suppressed. Distinct from the existing automatic codegen-input handling.
- **`loam init`** scaffolds a commented `loam.yaml` (the `rules:` + `ignore:`
  schema) and refuses to overwrite an existing file (exit 1).


## 0.1.2

- **`--format json`** is now available: a stable, machine-readable JSON report
  (schema-versioned, with tool/ruleset metadata, summary counts and findings)
  for agent and tooling integration. `markdown` and `html` remain on the roadmap.
- **Correct version everywhere.** The tool version is now sourced from the
  pubspec via a single in-code constant (`loamVersion`) instead of a hard-coded
  string, so the scan footer and SARIF/JSON tool block always match the release.
  A `docs-attest` check makes version drift across code and docs impossible.

## 0.1.1

- **Run as a compiled binary.** The analyzer needs a real Dart SDK at runtime;
  as an AOT executable (Homebrew) none sits beside the binary, so `loam scan`
  crashed with a `PathNotFoundException`. loam now resolves the SDK explicitly
  (`DART_SDK`, the Dart VM, or a `dart` on `PATH`) and passes it to the analyzer
  — works both as a pub global binary and via the Homebrew tap.
- **Homebrew install** (Apple Silicon macOS & Linux): `brew install silvio-l/loam/loam`.

## 0.1.0

First functional preview. The walking-skeleton pipeline is real end to end:

- **`loam scan`** — full audit via the tracer rule `unused-public-exports`:
  finds project-wide unused public API (exports, classes, methods,
  getters/setters, fields) on the resolved Dart element model, not regex.
- **`loam baseline --write`** — freeze the accepted state to `baseline.json`.
- **`loam gate`** — baseline/ratchet gate (default) and `--absolute` mode,
  with exit codes for CI.
- **Reporters** — `human` (default) and `sarif` (valid 2.1 for code-scanning).
- Hardened against false positives on real Riverpod/Drift codebases
  (part-file references, extensions, setter writes, pattern destructuring).

Not yet implemented (wired in `--help` as "coming soon"): `health`, `slop`,
`init`, `fix`, and the `json` / `markdown` / `html` reporters. See the roadmap
in the repository.

## 0.0.2

- Polished pub.dev page: logo, badges and clearer sections in the README.
  No functional changes (still early development).

## 0.0.1

- Initial preview release (name reservation). Walking-skeleton CLI: `loam scan`,
  `loam gate`, `loam baseline` are wired as stubs; the analysis pipeline and the
  tracer rule (`unused-public-exports`) are in active development. Not yet
  functional — see the roadmap in the repository.
