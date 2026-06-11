<p align="center">
  <img src="https://getloam.dev/loam-lockup.png" alt="loam.dev" width="440">
</p>

<p align="center"><strong>Codebase intelligence &amp; anti-AI-slop for Dart &amp; Flutter.</strong></p>

<p align="center">
  <a href="https://pub.dev/packages/loam"><img src="https://img.shields.io/pub/v/loam.svg?color=88C840" alt="pub version"></a>
  <a href="https://github.com/silvio-l/loam/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-88C840" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/built%20with-Dart%20analyzer-0175C2?logo=dart&logoColor=white" alt="Built with the Dart analyzer">
  <img src="https://img.shields.io/badge/status-preview-A2635A" alt="Status: preview">
</p>

---

> **loam.dev** is the product; **`loam`** is this CLI command and pub.dev package.
> Web: [getloam.dev](https://getloam.dev) · Source: [github.com/silvio-l/loam](https://github.com/silvio-l/loam)

`loam` is a Dart-native CLI for codebase intelligence and anti-AI-slop. It runs
on the Dart `analyzer` package — semantically accurate, project-wide, offline by
default — behind a baseline/ratchet CI gate that never paints a grown codebase
red on day one.

> **0.1.7.** Three rules are live end to end — `unused-public-exports`,
> `circular-dependencies` and `complexity-hotspots` — plus the `loam health`
> view. The remaining capabilities below are on the roadmap, each landing as its
> own rule behind the same stable `Rule` interface.

## What it catches

**Available now (0.1.7) — three live rules:** project-wide **unused public API**
(dead exports, classes, methods, getters/setters and fields), **circular
dependencies** between first-party libraries, and **complexity hotspots**
(cyclomatic/cognitive, aggregated into a `loam health` score) — emitted as
findings behind the baseline/ratchet gate, in `human`, `sarif`, `json`,
`markdown` or `html`.

Everything else is the **target surface** (🚧 = planned):

| Structural drift (deterministic, semantic) | AI-slop (deterministic **+** optional LLM) |
|---|---|
| ✅ Unused public exports, files, members | 🚧 Empty / swallowing `catch` blocks |
| ✅ Circular dependencies | 🚧 Narrative filler comments |
| 🚧 Code duplication (AST-normalised) | 🚧 Ungrounded `// ignore:` |
| ✅ Complexity hotspots + health score | 🚧 Duplicated helpers, dead guards |
| 🚧 Architecture-boundary violations | 🚧 Hallucinated / superfluous abstractions |

## What makes it different

- **🌱 Semantic, not regex** — resolved Dart element model + project-wide graphs. *(live)*
- **🔒 Baseline / ratchet gate (default)** — freeze today's findings; only **new** ones fail CI. *(live)*
- **♻️ Reproducible even with an LLM** — verdicts cached by `sha(code)+prompt@ver`, fixed thresholds decide. Same code = cache hit = stable verdict, zero token cost. *(🚧 planned)*
- **📄 Self-contained HTML report** — one offline file; toggle findings, copy a deterministic `prompt@ver` fix-prompt for your AI agent. *(live since 0.1.3; redesigned in 0.1.6)*
- **🔧 Configurable suppression** — `loam.yaml` rule toggles and project-relative `ignore:` globs, plus inline `// loam-ignore: <ruleId> – reason`; `loam init` scaffolds the file. *(in 0.1.3)*

## Install

```bash
dart pub global activate loam
```

Make sure `$HOME/.pub-cache/bin` is on your `PATH` (Dart prints a reminder if it
isn't). **To update**, re-run the exact same command. loam.dev reminds you when a
newer release is on pub.dev with one line on stderr (at most once a day); silence
it with `--no-update-check`, `LOAM_NO_UPDATE_CHECK`, or `update_check: false` in
`loam.yaml`. CI is always silent.

On Apple Silicon macOS / Linux you can skip the `PATH` step entirely with
Homebrew: `brew install silvio-l/loam/loam`.

<details>
<summary>Install the unreleased <code>dev</code> branch instead</summary>

```bash
dart pub global activate --source git https://github.com/silvio-l/loam.git \
    --git-path packages/loam_cli --git-ref dev
```
</details>

## Quick start

```bash
loam scan                          # full audit: all active rules, whole repo
loam scan /path/to/project         # same, positional path to project root
loam baseline --write              # freeze the accepted state to baseline.json
loam gate                          # CI: ratchet — only new findings fail (exit 1)
loam gate /path/to/project         # same, positional path to project root
loam health                        # cyclomatic/cognitive complexity distribution view
loam init                          # scaffold loam.yaml config in the project
```

All five commands (`scan`, `gate`, `health`, `init`, `baseline`) accept an optional positional
`[path]` as the project root. The explicit `-p`/`--project-root` option overrides the
positional path when both are given.

`loam --help` lists every command; planned ones are marked *(coming soon)*.

## Status

Functional release — three analysis rules live (`unused-public-exports`,
`circular-dependencies`, `complexity-hotspots`) plus the `loam health` view,
three more planned. Founding spec, domain glossary and architecture decisions
live in the [repository](https://github.com/silvio-l/loam).

## License

MIT © 2026 Silvio Lindstedt
