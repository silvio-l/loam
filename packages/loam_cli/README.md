<p align="center">
  <img src="https://getloam.dev/loam-lockup.png" alt="loam.dev" width="440">
</p>

<p align="center"><strong>Codebase intelligence &amp; anti-AI-slop for Dart &amp; Flutter.</strong></p>

<p align="center">
  <a href="https://pub.dev/packages/loam"><img src="https://img.shields.io/pub/v/loam.svg?color=88C840" alt="pub version"></a>
  <a href="https://github.com/silvio-l/loam/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-88C840" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/built%20with-Dart%20analyzer-0175C2?logo=dart&logoColor=white" alt="Built with the Dart analyzer">
  <img src="https://img.shields.io/badge/status-walking%20skeleton-A2635A" alt="Status: early development">
</p>

---

> **loam.dev** is the product; **`loam`** is this CLI command and pub.dev package.
> Web: [getloam.dev](https://getloam.dev) · Source: [github.com/silvio-l/loam](https://github.com/silvio-l/loam)

`loam` is a Dart-native CLI for codebase intelligence and anti-AI-slop. It runs
on the Dart `analyzer` package — semantically accurate, project-wide, offline by
default — behind a baseline/ratchet CI gate that never paints a grown codebase
red on day one.

> 🚧 **0.1.0 — early preview.** This is the first functional release. It ships
> **one** rule (`unused-public-exports`) end to end to prove the architecture;
> the rest of the capabilities below are on the roadmap, each landing as its own
> rule behind the same stable `Rule` interface.

## What it catches

**Available now (0.1.0):** project-wide **unused public API** — exports, classes,
methods, getters/setters and fields that nothing in the project references —
emitted as findings behind the baseline/ratchet gate, in `human` or `sarif`.

Everything else is the **target surface** (🚧 = planned, not in 0.1.0):

| Structural drift (deterministic, semantic) | AI-slop (deterministic **+** optional LLM) |
|---|---|
| ✅ Unused public exports, files, members | 🚧 Empty / swallowing `catch` blocks |
| 🚧 Circular dependencies | 🚧 Narrative filler comments |
| 🚧 Code duplication (AST-normalised) | 🚧 Ungrounded `// ignore:` |
| 🚧 Complexity hotspots + health score | 🚧 Duplicated helpers, dead guards |
| 🚧 Architecture-boundary violations | 🚧 Hallucinated / superfluous abstractions |

## What makes it different

- **🌱 Semantic, not regex** — resolved Dart element model + project-wide graphs. *(in 0.1.0)*
- **🔒 Baseline / ratchet gate (default)** — freeze today's findings; only **new** ones fail CI. *(in 0.1.0)*
- **♻️ Reproducible even with an LLM** — verdicts cached by `sha(code)+prompt@ver`, fixed thresholds decide. Same code = cache hit = stable verdict, zero token cost. *(🚧 planned)*
- **📄 Self-contained HTML report** — one offline file; toggle findings, copy a fix-prompt for your AI agent. *(🚧 planned)*

## Install

```bash
dart pub global activate loam
```

Make sure `$HOME/.pub-cache/bin` is on your `PATH` (Dart prints a reminder if it
isn't). **To update**, re-run the exact same command.

<details>
<summary>Install the unreleased <code>dev</code> branch instead</summary>

```bash
dart pub global activate --source git https://github.com/silvio-l/loam.git \
    --git-path packages/loam_cli --git-ref dev
```
</details>

## Quick start

```bash
loam scan                  # full audit: unused public API across the whole repo
loam baseline --write      # freeze the accepted state to baseline.json
loam gate                  # CI: ratchet — only new findings fail (exit 1)
```

`loam --help` lists every command; planned ones are marked *(coming soon)*.

## Status

Walking skeleton in progress. Founding spec, domain glossary and architecture
decisions live in the [repository](https://github.com/silvio-l/loam).

## License

MIT © 2026 Silvio Lindstedt
