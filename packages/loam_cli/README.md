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

> **0.1.16.** Twenty rules are live end to end — `unused-public-exports`,
> `circular-dependencies`, `architecture-boundaries`, `code-duplicates`, `complexity-hotspots`,
> `hardcoded-secrets`, `slop-empty-catch`, `slop-unjustified-ignore`,
> `slop-narrative-comment`, `slop-workflow-narration-comment`,
> `slop-placeholder-comment`, `slop-unimplemented-stub`, `slop-tautological-assertion`,
> `slop-undisposed-resource`, `slop-assertion-free-test`, `slop-setstate-after-async-gap`,
> `a11y-form-field-label`,
> `a11y-image-label`, `a11y-icon-button-label` and
> `a11y-interactive-semantics` — plus the `loam health` composite score. The
> remaining capabilities below are on the roadmap, each landing as its own
> rule behind the same stable `Rule` interface.

## What it catches

**Available now (0.1.16) — twenty live rules:** project-wide **unused public API**
(dead exports, classes, methods, getters/setters and fields), **circular
dependencies** between first-party libraries, **architecture
boundaries** (imports across a forbidden layer boundary configured in `loam.yaml`), **code duplicates** (AST-normalised
token hashing — exact and structurally identical copies; one Finding per cluster
with all locations), **complexity hotspots**
(cyclomatic/cognitive, aggregated into a `loam health` score; scans `lib/` and
`bin/` by default — configure with `source_dirs` in `loam.yaml`), **AI-slop**
(`slop-empty-catch` — empty and comment-only `catch` bodies;
`slop-unjustified-ignore` — `// ignore:` and `// ignore_for_file:` directives
without a written justification; `slop-narrative-comment` — `//` comments that
merely restate the declaration name, plus banner comments, empty category
labels, emoji-only decoration, end-of-block markers, and vague TODOs;
`slop-workflow-narration-comment` — sequential `Step 1:`/`First,`/`Next,`/
`Then,`/`Finally,` comments narrating a function body step-by-step;
`slop-placeholder-comment` — comments such as `// ... rest of code` or `// your
code here` standing in for code that is missing;
`slop-unimplemented-stub` — functions and methods in `lib/`/`bin/` whose whole
body is `throw UnimplementedError()`;
`slop-tautological-assertion` — `expect`/`expectLater` calls that compare a constant with a
constant or a value with itself, such as `expect(true, isTrue)`, and so cannot fail;
`slop-undisposed-resource` — fields a `State` (or a class with its own
`dispose()`) creates itself, such as a `TextEditingController` or a
`Timer.periodic`, that `dispose()` never releases;
`slop-assertion-free-test` — `test`/`testWidgets` bodies that never `expect`, `verify`
or `check` anything, not even through your own helper functions;
`slop-setstate-after-async-gap` — `setState` in a Flutter `State` after an `await`
or in a `Future.then` callback with no `mounted` check, which throws once the screen is closed;
`hardcoded-secrets` — API keys, passwords and tokens written into string
literals, offline and with the value never echoed), and **accessibility** (WCAG 1.1.1 — Flutter
images without a semantic label; WCAG 4.1.2 — icon buttons, gesture/ink-well
widgets with a pure icon child, and generic interactive widgets without an
accessible name; WCAG 3.3.2 — form fields without a label) — emitted as Findings
behind the baseline/ratchet gate, in `human`, `sarif`, `json`, `markdown`, `html` or `agent` (a compact, capped list for agents).

Everything else is the **target surface** (🚧 = planned):

| Structural drift (deterministic, semantic) | AI-slop (deterministic **+** optional LLM) | Accessibility (WCAG, semantic) |
|---|---|---|
| ✅ Unused public exports, files, members | ✅ Ungrounded `// ignore:` (slop-unjustified-ignore) | ✅ Image without semantic label (a11y-image-label, WCAG 1.1.1) |
| ✅ Circular dependencies | ✅ Empty / comment-only `catch` blocks (slop-empty-catch) | ✅ Icon button without accessible name (a11y-icon-button-label, WCAG 4.1.2) |
| ✅ Code duplicates (AST-normalised) | ✅ Narrative filler comments (slop-narrative-comment) | ✅ Form field without label (a11y-form-field-label, WCAG 3.3.2) |
| ✅ Complexity hotspots + health score | ✅ Sequential workflow narration (slop-workflow-narration-comment) | ✅ Interactive widget without semantics (a11y-interactive-semantics, WCAG 4.1.2) |
| | ✅ Hardcoded secrets (hardcoded-secrets) | |
| | ✅ Tautological test assertions (slop-tautological-assertion) | |
| | ✅ setState after an async gap (slop-setstate-after-async-gap) | |
| ✅ Architecture-boundary violations (architecture-boundaries) | 🚧 Hallucinated / superfluous abstractions | |

## What makes it different

- **🌱 Semantic, not regex** — resolved Dart element model + project-wide graphs. *(live)*
- **🔒 Baseline / ratchet gate (default)** — freeze today's findings; only **new** ones fail CI. *(live)*
- **♻️ Reproducible even with an LLM** — verdicts cached by `sha(code)+prompt@ver`, fixed thresholds decide. Same code = cache hit = stable verdict, zero token cost. *(🚧 planned)*
- **📄 Self-contained HTML report** — one offline file; toggle findings, copy a deterministic `prompt@v3` fix-prompt (scope-limited to your project, Karpathy-structured instructions) for your AI agent. *(live since 0.1.3; redesigned in 0.1.16)*
- **🔧 Configurable suppression** — `loam.yaml` rule toggles and project-relative `ignore:` globs, plus inline `// loam-ignore: <ruleId> [until=YYYY-MM-DD] – reason`; unused, expired or reason-less directives are reported as warnings and `scan`/`gate` show suppressions per rule; `loam init` scaffolds the file. *(in 0.1.3)*
- **🧭 Preventive recommendations for agents** — after a run with findings, one curated recommendation per fired rule class, addressed to the agent to propose to you for your persistent instructions (e.g. `CLAUDE.md`); deterministic, no LLM call, structured in `--format json`. *(live)*

## Install

```bash
dart pub global activate loam
```

Make sure `$HOME/.pub-cache/bin` is on your `PATH` (Dart prints a reminder if it
isn't). loam.dev keeps itself current: at most once a day it checks pub.dev in
the background, updates a pub install or a standalone release binary by itself
(the binary only after its `.sha256` matches), and prints `brew upgrade loam` for
a Homebrew install. The next run reports the update on stderr, including rules it
added or removed. Pin a version with `required_version` in `loam.yaml` (never
updated; `loam gate` stops on a mismatch). Nothing happens in CI, with
`LOAM_OFFLINE`, or when turned off (`--no-update-check`, `LOAM_NO_UPDATE_CHECK`,
`update_check: false`; `LOAM_NO_AUTO_UPDATE` / `auto_update: false` keep only the
notice). `loam --version` prints the running version, install channel and path.

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
loam watch                         # re-run the audit after every change, show new/resolved
loam scan --changed                # report only files changed in the working copy
loam gate --staged                 # pre-commit: gate only files staged in git
loam gate --since origin/main      # CI/PR: gate only files changed since a ref
loam gate --profile strict         # heuristic rules block too (default: core)
loam health                        # composite score (findings + complexity) & grade
loam init                          # scaffold loam.yaml (incl. detected architecture layers)
loam a11y                          # accessibility audit: WCAG-focused rules only
loam a11y /path/to/project         # same, positional path to project root
loam slop                          # AI-slop audit: slop-focused rules only
loam slop /path/to/project         # same, positional path to project root
```

`--staged`, `--since <ref>` and `--changed` (on `scan` and `gate`) keep the analysis
project-wide and narrow only the report and the gate to the files git lists as
changed; they are mutually exclusive, and outside a git repository or with an
unknown ref loam exits with 64. Pre-commit hook: `exec dart pub global run loam gate --staged` (use this form in hooks and CI: the pub shim sits in `%LOCALAPPDATA%\Pub\Cache\bin` on Windows, not `~/.pub-cache/bin`).

All eight commands (`scan`, `watch`, `gate`, `health`, `init`, `baseline`, `a11y`, `slop`) accept an
optional positional `[path]` as the project root. The explicit `-p`/`--project-root`
option overrides the positional path when both are given.

**Rule profiles.** `loam gate` blocks only on the `core` profile by default:
rules with a near-zero false-positive rate (`circular-dependencies`,
`architecture-boundaries`, `unused-public-exports`, `slop-empty-catch`, `slop-tautological-assertion`, `slop-unjustified-ignore`,
`hardcoded-secrets`). The heuristic and threshold-based rules show up as a hint;
`--profile strict` (or `profile: strict` in `loam.yaml`) lets them block too.
The baseline is the same for both; a gate that was red only because of strict
rules turns green after upgrading, so set `profile: strict` to keep the old
behaviour.

`loam --help` lists every command; planned ones are marked *(coming soon)*.

`scan`, `gate`, `baseline`, `slop`, `a11y` and `health` all show a live
loading/analysis progress bar in an interactive terminal, auto-disabled under
CI or when piped; silence it explicitly with `--no-progress` or
`LOAM_NO_PROGRESS`.

`--timing` prints wall-clock time per phase (setup, resolve or parse, rules,
suppression, update-check; report for `scan`) and per rule to stderr after
the run; stdout stays unchanged.

The analyzer keeps its summaries in `.dart_tool/loam/analyzer/` between runs,
which speeds up resolving; results are the same either way. Switch it off with
`--no-cache` or `cache: false` in `loam.yaml`. `loam slop` only parses the
project and does not need it.

A run never hangs silently: after 10 minutes (`--timeout <duration>` or
`LOAM_TIMEOUT`, for example `90s`, `30m`, `1h`; `0` or `off` disables it) loam
aborts, prints the running phase and rule to stderr and exits with code `124`
- distinct from `1` (findings), `64` (usage) and `78` (configuration), so a
hook can tell a timeout from a red gate. stdout stays untouched.

## Status

Functional release — twenty analysis rules live (`unused-public-exports`,
`circular-dependencies`, `architecture-boundaries`, `code-duplicates`, `complexity-hotspots`,
`hardcoded-secrets`, `slop-empty-catch`, `slop-unjustified-ignore`,
`slop-narrative-comment`, `slop-workflow-narration-comment`,
`slop-placeholder-comment`, `slop-unimplemented-stub`, `slop-tautological-assertion`,
`slop-undisposed-resource`, `slop-assertion-free-test`, `slop-setstate-after-async-gap`,
`a11y-form-field-label`,
`a11y-image-label`, `a11y-icon-button-label`,
`a11y-interactive-semantics`) plus the `loam health` composite score;
the remaining capabilities land as individual rules behind the same `Rule`
interface. Founding spec, domain
glossary and architecture decisions live in the
[repository](https://github.com/silvio-l/loam).

## License

MIT © 2026 Silvio Lindstedt
