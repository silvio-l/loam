# Changelog

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
