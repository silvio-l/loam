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

`loam` catches the **structural drift** and **AI-generated slop** that
`dart analyze` never sees — behind a baseline/ratchet CI gate that never paints a
grown codebase red on day one. Built on the Dart `analyzer` package: semantically
accurate, project-wide, offline by default.

## What it catches

| Structural drift (deterministic, semantic) | AI-slop (deterministic **+** optional LLM) |
|---|---|
| Unused public exports, files, members | Empty / swallowing `catch` blocks |
| Circular dependencies | Narrative filler comments |
| Code duplication (AST-normalised) | Ungrounded `// ignore:` |
| Complexity hotspots + health score | Duplicated helpers, dead guards |
| Architecture-boundary violations | Hallucinated / superfluous abstractions |

## What makes it different

- **🌱 Semantic, not regex** — resolved Dart element model + project-wide graphs.
- **🔒 Baseline / ratchet gate (default)** — freeze today's findings; only **new** ones fail CI.
- **♻️ Reproducible even with an LLM** — verdicts cached by `sha(code)+prompt@ver`, fixed thresholds decide. Same code = cache hit = stable verdict, zero token cost.
- **📄 Self-contained HTML report** — one offline file; toggle findings, copy a fix-prompt for your AI agent.

## Install

```bash
dart pub global activate loam
```

## Quick start

> 🚧 **Early development.** The walking skeleton wires the pipeline and the tracer
> rule (`unused-public-exports`); the remaining capabilities land as individual
> rules. Commands below are the target surface.

```bash
loam scan                 # full audit: every active rule, whole repo
loam baseline --write      # freeze the accepted state
loam gate                  # CI: ratchet — only new findings fail
```

## Status

Walking skeleton in progress. Founding spec, domain glossary and architecture
decisions live in the [repository](https://github.com/silvio-l/loam).

## License

MIT © 2026 Silvio Lindstedt
