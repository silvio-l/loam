# Changelog

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
