<p align="center">
  <img src="assets/brand/lockup-horizontal-dark.png" alt="loam.dev" width="460">
</p>

<p align="center">
  <strong>Codebase intelligence &amp; anti-AI-slop for Dart &amp; Flutter.</strong>
</p>

<p align="center">
  Catch the <em>structural drift</em> and <em>AI-generated slop</em> that
  <code>dart analyze</code> never sees — behind a baseline/ratchet CI gate that
  never paints a grown codebase red on day one.
</p>

<p align="center">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-88C840">
  <img alt="Built with the Dart analyzer" src="https://img.shields.io/badge/built%20with-Dart%20analyzer-0175C2?logo=dart&logoColor=white">
  <img alt="LLM layer: cache-stabilised" src="https://img.shields.io/badge/LLM%20layer-cache--stabilised-88C840">
  <img alt="Status: early development" src="https://img.shields.io/badge/status-walking%20skeleton-A2635A">
</p>

> **loam.dev** is the product; **`loam`** is the CLI command and the pub.dev
> package name. Built on the Dart `analyzer` package — semantically accurate,
> project-wide, offline by default.

---

## Why loam.dev?

AI coding agents generate Dart/Flutter faster than anyone can review. Two classes
of damage slip straight past the built-in `dart analyze`:

1. **Structural drift** — dead code, duplication, circular dependencies,
   complexity hotspots, violated architecture boundaries.
2. **AI-slop** — empty `catch` blocks, narrative filler comments, ungrounded
   `// ignore:`, duplicated helpers, dead guard clauses, hallucinated abstractions.

JS/TS has mature tools for this. **Dart/Flutter has had nothing free and
slop-aware** — the closest is DCM, but its best rules sit behind a commercial
license and it has no LLM-backed slop detection. loam.dev closes that gap.

## What it catches

| Structural drift (deterministic, semantic) | AI-slop (deterministic **+** optional LLM) |
|---|---|
| Unused public exports, files, members | Empty / swallowing `catch` blocks |
| Circular dependencies | Narrative filler comments |
| Code duplication (AST-normalised) | Ungrounded `// ignore:` |
| Complexity hotspots + health score | Duplicated helpers, dead guards |
| Architecture-boundary violations | Hallucinated / superfluous abstractions |

Every capability is one plugin behind a single, stable `Rule` interface — adding
a feature never changes the pipeline.

## What makes it different

- **🌱 Semantic, not regex.** Structural rules use the resolved Dart element
  model and project-wide graphs — real whole-program resolution, not heuristics.
- **🔒 Baseline / ratchet gate (the default).** Freeze today's accepted findings;
  from then on only **new** findings fail CI. Monotone improvement, no day-one red.
- **♻️ Reproducible, even with an LLM.** The LLM proposes `{score, label}` →
  cached by `sha(code)+prompt@ver` → fixed thresholds decide. Same code = cache
  hit = stable verdict = zero token cost. No flaky gate.
- **📄 Self-contained HTML report.** A single offline `.html` artifact: toggle
  findings, then copy a curated **fix-prompt** straight into your AI agent. No
  server, no hosting, no dashboard.
- **📦 Dart-native.** Installed via `dart pub global activate` (pub.dev from v1.0;
  Git source pre-release). SemVer; `ruleset@ver` + `prompt@ver` are part of the
  baseline identity.

## Quick start

> 🚧 **Early development (pre-release).** The walking skeleton proves the architecture
> with one end-to-end rule (`unused-public-exports`); the remaining capabilities land
> as individual rules. Commands below are the target surface.

### Install (pre-release — Git source)

Install directly from the `dev` branch until v1.0 is published to pub.dev:

```bash
dart pub global activate --source git https://github.com/silvio-l/loam.git \
    --git-path packages/loam_cli --git-ref dev
```

Make sure `$HOME/.pub-cache/bin` is on your `PATH` (Dart prints a reminder if it
isn't). To update, simply re-run the command above.

> **From v1.0 (pub.dev release):** `dart pub global activate loam`

### Use

# Available now (walking skeleton — tracer rule `unused-public-exports`):
```bash
loam scan                          # full audit: every active rule, whole repo
loam baseline --write              # freeze the remaining, accepted state
loam gate                          # CI from now on — ratchet: only new findings fail
```

# Coming soon (wired in `loam --help`, not yet implemented):
```bash
loam init                          # scaffold loam.yaml config in the project
loam health                        # project health score: complexity, drift, slop
loam slop                          # AI-slop audit: slop-focused rules only
loam fix --safe                    # apply mechanical fixes
```

**Onboarding an existing repo** (turn an established codebase green, then keep it
green): `scan` → clean up → `baseline --write` → `gate` in CI. A later cleanup
round just repeats it. Greenfield? `loam gate --absolute` needs no baseline.

## Built for the terminal

<p align="center">
  <img src="assets/brand/terminal-banner.png" alt="loam.dev terminal banner" width="300">
</p>

Machine-readable output for CI and agents, a human-readable report for you:

```
--format human        # default, readable terminal output      (available)
--format sarif        # CI / code-scanning                      (available)
--format json         # agent / tooling integration             (coming soon)
--format markdown     # PR / docs embedding                     (coming soon)
--format html         # interactive, self-contained report      (coming soon)
```

## Status & roadmap

Walking skeleton in progress. The founding spec lives in
[`docs/PRD.md`](./docs/PRD.md); the canonical domain vocabulary in
[`CONTEXT.md`](./CONTEXT.md); architecture decisions in [`docs/adr/`](./docs/adr/).

## Repo layout

This is a monorepo — everything that makes up loam.dev:

| Path | What |
|---|---|
| [`packages/loam_cli/`](./packages/loam_cli/) | The Dart CLI (pub.dev package `loam`). The actual tool. |
| [`web/`](./web/) | Promo / docs website (static, free-tier). Scaffold. |
| [`skill/`](./skill/) | Claude skill/plugin that drives `loam` for agents. Scaffold. |
| [`assets/brand/`](./assets/brand/) | Logo, colors, terminal banner. See its [README](./assets/brand/README.md). |
| [`docs/`](./docs/) | Founding spec + architecture decisions. |

## Develop

The Dart package lives in `packages/loam_cli/`:

```bash
cd packages/loam_cli
dart pub get
dart format --output=none --set-exit-if-changed bin lib test
dart analyze --fatal-infos --fatal-warnings
dart test
dart run bin/loam.dart scan
```

loam.dev's first test target is **its own codebase** — the tool that finds slop
and drift must carry none itself.

## License

MIT © 2026 Silvio Lindstedt
