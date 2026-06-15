# Changelog

## 0.1.12

- **`loam.yaml` is now discovered by walking up to your git repository root —
  and monorepo configs layer.** Previously loam only read a `loam.yaml` sitting
  exactly at the analysed project root. Now it searches upward from that root to
  the enclosing git repository root (the directory holding `.git`), just like
  Dart's own `analysis_options.yaml` — so a config at your repo root is honoured
  even when you analyse a sub-package. Every `loam.yaml` on the way is layered
  farthest→nearest: a repo-root file provides shared defaults and a nearer
  (per-package) file builds on top of it. Merge rules, nearer wins: `rules` are
  merged per ruleId, `ignore` lists are concatenated (farther first,
  de-duplicated), and `source_dirs` / `update_check` / `a11y` override while an
  omitted key inherits the farther value. `ignore` globs are still matched
  relative to the analysed project root, regardless of which layer declared
  them. The walk is **bounded at the git root**, so discovery stays
  repo-relative and reproducible across machines and CI — a `loam.yaml` above
  the repository (e.g. in `$HOME`) is never picked up. With no git root, only
  `<projectRoot>/loam.yaml` is read. Fully backward compatible: a single
  `loam.yaml` at the project root yields exactly the previous result.

## 0.1.11

- **New: accessibility audits for Flutter — the `loam a11y` command and four
  WCAG-grounded rules.** loam.dev now ships an `a11y` rule category and a
  dedicated `loam a11y` command (plus a `--no-a11y` opt-out on the broader
  scans) that flag missing accessible names and labels in Flutter widget trees.
  Every rule analyses the resolved element model — local classes that merely
  share a name with a Flutter widget are never flagged — and stays deliberately
  AST-only (runtime contrast, focus order and touch-target sizes are out of
  scope):
  - **`a11y-image-label`** (WCAG 1.1.1) — `Image` / `Image.asset` /
    `Image.network` / `.file` / `.memory` with no `semanticLabel` and no
    `excludeFromSemantics: true`; an explicit empty label still counts as
    missing.
  - **`a11y-icon-button-label`** (WCAG 1.1.1 / 4.1.2) — `IconButton` with no
    `tooltip` and no enclosing `Semantics(label: …)`, plus `GestureDetector` /
    `InkWell` whose direct child is a bare `Icon`.
  - **`a11y-form-field-label`** (WCAG 1.3.1 / 3.3.2 / 4.1.2) — `TextField` /
    `TextFormField` with neither an `InputDecoration(labelText: …)` (nor
    `hintText` as a fallback) nor an enclosing `Semantics(label: …)`.
  - **`a11y-interactive-semantics`** (WCAG 4.1.2) — generic and custom
    interactive widgets carrying `onTap` / `onPressed` / `onLongPress` but no
    `Semantics(label: …)` ancestor. Flutter built-ins already covered by the
    sibling rules are excluded, so the two never double-report.
- **New: the `loam slop` command and the first three deterministic anti-AI-slop
  rules.** A new `slop` rule category and a `loam slop` command surface the
  low-effort patterns AI agents commonly leave behind. All three are
  deterministic AST/token checks (no LLM, no token cost), skip generated files
  automatically, and are suppressible per project via `loam.yaml` or inline with
  `// loam-ignore: <rule> – <reason>`:
  - **`slop-unjustified-ignore`** (info) — `// ignore:` and
    `// ignore_for_file:` directives with no written justification, inline or on
    the preceding line.
  - **`slop-empty-catch`** (warning) — `catch` blocks whose body is empty or
    contains only comments. Extends the built-in `empty_catches` lint to the
    comment-only variant; bodies with a `rethrow`, `throw` or any logging call
    are never flagged.
  - **`slop-narrative-comment`** (info) — `//` comments immediately before a
    declaration that merely restate its name (`// build` before `void build()`)
    or use a fixed narrative phrase (`constructor`, `getter`, `setter`,
    `build method`). Deliberately narrow: `///` Dartdoc and informative comments
    are never flagged — precision over recall.
- All seven new rules run in `loam scan`, `gate` and `baseline` and are visible
  in every reporter (`human`, `json`, `sarif`, `markdown`, `html`), with stable,
  line-shift-robust fingerprints so the baseline only reacts to genuinely new
  findings.

## 0.1.10

- **New rule: `code-duplicates` — loam.dev now finds copy-pasted and
  structurally identical code across your whole project.** It enumerates code
  blocks over the resolved AST, normalises each into a token sequence, and
  clusters recurring blocks project-wide with a Rabin-Karp rolling hash. Every
  cluster becomes exactly **one** Finding (`Severity.warning`) that lists all
  locations and points at the first occurrence, with a stable Fingerprint so the
  Baseline survives line shifts and only reacts when a copy is added or removed.
  Generated files are excluded, and a conservative minimum-token threshold keeps
  short boilerplate out. Like `complexity-hotspots`, it scans `lib/` and `bin/`
  by default — `test/`, `tool/` and `example/` duplicates are not reported
  unless you widen `source_dirs` in `loam.yaml`. It catches **Type-1** (exact,
  whitespace- and comment-independent) and **Type-2** (renamed identifiers and
  literals) duplicates; gapped duplicates are out of scope. The rule runs in `loam scan`,
  `gate` and `baseline` and is visible in every reporter (`human`, `json`,
  `sarif`, `markdown`, `html`); suppress it per project via `loam.yaml` or inline
  with `// loam-ignore: code-duplicates`.
- **Fewer false positives on Flutter widget code.** The detector uses
  *consistent* (alpha) renaming — each distinct identifier and literal gets a
  stable per-block slot, preserving the repetition pattern — plus a
  distinct-token-type gate. Together they stop reporting structurally identical
  but semantically distinct widget boilerplate (parallel factories, builders and
  state widgets) as duplicates, while still catching genuine renamed copies. The
  hardening was validated on a real-world Flutter codebase: precision in
  production code improved with **zero** new missed duplicates.

## 0.1.9

- **`unused-public-exports` now reads the stack it runs on — far fewer false
  positives on real Dart and Flutter projects.** The rule used to judge a
  throwaway app and a published package the same way, and it recognised only a
  handful of code-gen frameworks, so on real codebases it flagged deliberately
  public API and generated or annotated symbols as "dead". Three changes fix
  that. All of them read from the resolved element model (never source text),
  and each one only ever **removes** a false positive — upgrading can lower your
  finding count but never raises it, so the baseline/ratchet gate never paints a
  project red:
  - **App vs. publishable package.** loam reads the target's `pubspec.yaml` once
    at load. On a *publishable* package (anything without `publish_to: none`) the
    deliberately public top-level `lib/` API is no longer reported as unused —
    that surface exists to be consumed from outside — while genuinely dead
    `lib/src/` internals are still reported. An **app** (`publish_to: none`)
    behaves exactly as it did before. Publishability is conservative: when it
    cannot be determined, loam assumes publishable.
  - **Two more visibility annotations.** Public members marked `@internal`
    (package:meta) or `@visibleForOverriding` are no longer reported, joining the
    existing `@visibleForTesting` and `@pragma('vm:entry-point')` exemptions.
  - **A wider code-gen registry.** Symbols produced or annotated by six more
    generators count as code-gen input instead of dead API: `injectable` /
    `get_it`, `auto_route`, `mockito`, Isar, ObjectBox / floor and Hive — plus
    the generated suffixes `*.gr.dart`, `*.config.dart`, `*.mocks.dart` and
    `*.pb.dart`, on top of the existing `*.g.dart` / `*.freezed.dart`.
- **New: a `stack:` line in `loam scan`.** Human-format scans print a one-line
  stack profile — the detected code-gen generators, whether it is a Flutter
  project, and publishability — so you can see at a glance what loam inferred
  about your project. It is purely diagnostic: it feeds the report and the
  publishable-vs-app decision but never makes a suppression call on its own.
  JSON, SARIF, HTML and Markdown output are unchanged.

## 0.1.8

- **Complexity now scans `bin/` too, and the scope is configurable.** The
  `complexity-hotspots` rule and `loam health` measured only `lib/`, silently
  skipping `bin/` entrypoint logic (real, shipping code). They now measure
  `lib/` **and** `bin/` by default. Configure it per project with `source_dirs`
  in `loam.yaml` — e.g. add `test`/`tool` to widen, or narrow to `lib` only.
  Generated files stay excluded regardless; `test/`, `example/` and `tool/`
  remain off by default (intentionally high or low complexity = noise). The
  structural rules `circular-dependencies` and `unused-public-exports` are an
  inherent `lib/` concept and are deliberately unaffected.
- **Channel-aware update notice.** The once-a-day update line now prints the
  upgrade command that matches how loam was actually installed —
  `brew upgrade loam` for a Homebrew binary, `dart pub global activate loam`
  otherwise. This prevents the trap where a Homebrew user follows the generic
  pub.dev advice and installs a second, unreachable `~/.pub-cache` copy that
  never shadows the Homebrew binary, so the "update" silently does nothing.
- **New: `loam --version`.** Prints the running version, the install channel and
  the resolved executable path (e.g. `install: homebrew · …/Cellar/loam/…`). Use
  it to confirm an upgrade actually landed on the binary on your `PATH`. The
  version comes from the same constant the report footer uses, so the two can
  never disagree. The Homebrew formula's `brew test` now asserts this version,
  catching a stale or mis-rendered formula.
- **Reports now surface suppression and scan scope.** A `0 findings — clean`
  result was indistinguishable from "nothing scanned" or "real findings
  knowingly suppressed". Every reporter now shows how many findings were
  suppressed (`// loam-ignore:` + `loam.yaml` globs) and a scope line —
  files analysed (and how many under `lib/`), lines, and which rules ran — so a
  clean scan can be trusted as comprehensive. JSON is now `schemaVersion: 3`
  with a `summary.suppressed` count and a `scan` object; SARIF carries the same
  in a run-level property bag; human/Markdown gain a scope line; the HTML report
  shows scope rows and a suppressed note. Findings and fingerprints are
  unchanged, so baselines do not churn.

## 0.1.7

- **Fixed: Flutter SDK no longer crashes the scan.** On a standard Flutter
  install only `flutter/bin` is on `PATH`, where `dart` is a wrapper script;
  loam resolved the SDK two levels up to the Flutter checkout root (which has no
  `lib/_internal`) and the analyzer crashed with a raw `PathNotFoundException`.
  loam now redirects into `<flutterRoot>/bin/cache/dart-sdk`. When no usable SDK
  can be found at all, loam prints an actionable message (set `DART_SDK=…`) and
  exits 78 instead of dumping a stack trace.
- **Agent-proof findings: every finding now carries a `kind` and a `remedy`.**
  loam's output is read by AI agents as well as humans, and a bare fact invites
  mis-triage. `complexity-hotspots` now distinguishes `flutter-widget-build`
  from `logic`; `circular-dependencies` states the cycle is real regardless of
  any platform/strategy factory layered on top; every finding names the concrete
  next action. JSON output is now `schemaVersion: 2` with `kind` and `remedy` as
  first-class fields; SARIF carries them in the property bag; Markdown gains a
  Remedy column. Fingerprints are unchanged, so baselines do not churn.

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
- **Positional project path.** `scan`, `gate`, `health`, `init` and `baseline` now accept
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
