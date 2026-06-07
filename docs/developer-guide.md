# loam.dev Developer & Tool Guide

<!-- guide:start -->

A practical reference for using **loam.dev** — the Dart/Flutter codebase intelligence
CLI — covering core concepts, CLI commands, output formats, and how loam.dev handles
code generators automatically.

> **Naming.** The product is **loam.dev**; `loam` (no `.dev`) is exclusively the CLI
> command and the pub.dev package name. The capitalised form without `.dev` is
> anti-vocabulary — always write `loam.dev` in prose.

---

## Core concepts

<!-- concepts:start -->

### Finding

A **Finding** is a single analysis result:

```
{ ruleId, severity, location, message, fingerprint }
```

Every Finding has a stable **Fingerprint** — a position-robust hash used for
baseline diffing. `ruleId` identifies which Rule produced it; `severity` is one of
`error`, `warning`, or `info`.

> **Vocabulary note:** "Issue" refers to project tracker tickets, not analysis
> results. Always use "Finding" in the context of loam.dev output.

### Severity

Three levels, in descending order: `error` · `warning` · `info`.

### Rule

A **Rule** is one analysis unit behind the shared `Rule` interface. Each capability
(unused public API, slop detection, cycle detection …) is a separate Rule. Adding a
new Rule never changes the analysis pipeline — only the rule list.

Rules are either:

- **DeterministicRule** — pure AST/element-model analysis. Reproducible, offline, no
  cost. All currently active rules are deterministic.
- **LlmRule** *(planned)* — uses an LLM for `{score, label}` via a versioned
  **VerdictCache** (`sha(code)+prompt@ver`). Same code = cache hit = stable verdict
  = zero token cost. The LLM path is never hit ungached in the gate (Invariant 2).

Currently active rules:

| Rule ID | What it finds |
|---|---|
| `unused-public-exports` | Public API members (classes, methods, getters/setters, fields, enums, typedefs) with no references anywhere in the project — on the resolved element model, not regex. |

All other rules in the `CONTEXT.md` target surface are planned (🚧).

### Baseline

A **Baseline** is a frozen snapshot of accepted Findings written to `baseline.json`.
The Gate uses it as a reference: only *new* Findings (not in the baseline) count
against the gate decision. A Baseline is the bridge between a full audit and
ongoing CI hygiene.

### Gate

The **Gate** is loam.dev's pass/fail decision with an exit code, designed for CI.

Two modes:

| Mode | Behaviour | When to use |
|---|---|---|
| **Ratchet** (default) | Only NEW Findings fail. Kept (frozen) and fixed Findings are transparent. The score can only improve. | All projects with existing code (established repos). |
| **Absolute** (`--absolute`) | All current Findings are evaluated against a fixed threshold (default 0). Baseline is ignored. | Greenfield projects, or pipelines requiring zero findings. |

**Ratchet is the default.** This means an existing codebase never goes red on day
one — you baseline the current state and only new regressions fail CI.

### Reporter

A **Reporter** converts Findings into output. It is a pure renderer: it has no
influence on the gate decision or exit code (Invariant 4).

Available formats: see [Output formats](#output-formats) below.

<!-- concepts:end -->

---

## Reproducibility

<!-- reproducibility:start -->

loam.dev is deterministic by design:

> **Same code + same `ruleset@ver`** ⇒ **identical Findings.**

The `ruleset@ver` is stored in `baseline.json` and in SARIF/JSON output alongside
the tool version. When the ruleset version changes (a rule is added or its logic is
updated), the gate warns and suggests a baseline refresh. There is no silent
rule-version drift.

For the LLM layer *(planned)*: `sha(code)+prompt@ver` keys the VerdictCache, so
even the LLM path is deterministic per code snapshot.

<!-- reproducibility:end -->

---

## CLI commands

<!-- commands:start -->

Install via Homebrew (recommended on Apple Silicon macOS / Linux):

```bash
brew install silvio-l/loam/loam
```

Or via pub.dev (all platforms):

```bash
dart pub global activate loam
```

### Global option

```
--format <format>    Output format (default: human).
```

Available formats: `human` · `sarif` · `json` · `markdown` · `html` *(planned)*.

### `loam scan`

Full audit: runs all active rules across the whole project, baseline-independent.
Use this to see every Finding regardless of what is in the baseline.

```bash
loam scan                              # current directory
loam scan -p /path/to/project          # explicit project root
loam scan --format json                # machine-readable output
```

Exit code `1` when any Findings are present; `0` when clean.

This is the **Vollaudit** command — start here to assess a new project before
freezing a baseline.

### `loam baseline`

Show, write, or update the baseline (`baseline.json`).

```bash
loam baseline                          # show current baseline findings
loam baseline --write                  # freeze current findings as baseline
loam baseline --update                 # refresh an existing baseline
```

**Baseline onboarding flow** for an existing project:
1. `loam scan` — see everything
2. Fix or accept what you can
3. `loam baseline --write` — freeze the accepted state
4. `loam gate` in CI from now on

### `loam gate`

CI gate: evaluates current Findings against the baseline.

```bash
loam gate                              # ratchet mode (default): only new findings fail
loam gate --absolute                   # absolute mode: all findings evaluated, threshold 0
loam gate --format sarif               # SARIF output (CI code-scanning)
```

Exit code `1` when the gate fails; `0` when it passes.

Prints a terse summary line:
```
loam gate: N neu, M eingefroren, K gefixt — grün.
```

### `loam health` *(coming soon)*

Project health score: aggregates complexity, drift, and slop metrics into a single
score. Not yet implemented.

### `loam slop` *(coming soon)*

AI-slop audit: runs slop-focused rules only (empty `catch`, filler comments, dead
guards, …). Not yet implemented.

### `loam init`

Scaffold a `loam.yaml` configuration in the current project.

```bash
loam init                    # writes loam.yaml in the current directory
loam init -p /path/to/proj   # specify a different project root
```

If `loam.yaml` already exists, the command refuses to overwrite it and exits with
code 1 — no silent data loss. Delete or edit the file manually to replace it.

The generated `loam.yaml` includes commented examples for the `rules:` and `ignore:`
sections. The file is valid and loadable as-is (all examples are YAML comments, so
no rule toggles are active until you uncomment them).

### `loam fix` *(coming soon)*

Apply mechanical fixes for Findings that have a safe auto-fix. Not yet implemented.

<!-- commands:end -->

---

## Output formats

<!-- formats:start -->

All formats are selected with the global `--format` flag and work with every command
that produces Finding output.

| Format | Status | Use case |
|---|---|---|
| `human` | **Available** | Default. Human-readable terminal output with colour (when TTY). |
| `sarif` | **Available** | SARIF 2.1 JSON for CI code-scanning tools (GitHub, GitLab, …). |
| `json` | **Available** | Machine-readable JSON for agent/tooling integration. |
| `markdown` | **Available** | Markdown report for PR comments, docs embedding, LLM pipelines. |
| `html` | **Planned** | Self-contained `loam-report.html` with toggleable Findings and a copy-to-clipboard fix-prompt. |

The **Reporter is a pure renderer** — format choice never affects exit codes or
gate decisions.

<!-- formats:end -->

---

## Automatic codegen-input suppression

<!-- codegen-suppression:start -->

### Why your generated-code inputs are not reported

loam.dev does **not** report public members of code-generator *input* classes as
unused. This is automatic — no comments, no configuration required.

**Why?** Code generators like Drift, freezed, Riverpod, and json_serializable read
your class at *build time* and produce a companion `*.g.dart` or `*.freezed.dart`
file. The generated file uses every member you declared, but the Dart element model
sees no *static* reference from your hand-written code to those members. Without
suppression, loam.dev would report every column in a Drift `Table` class as unused —
a false positive.

### How detection works

Detection is **semantic** (element model, not source text). Classification uses
"first match wins" over three signals, in this order:

#### 1. Base-type registry (`base_type:<name>`)

If the class (or any supertype in its chain) is one of the known Drift base types,
it is classified as a codegen input:

| Matched type | Example |
|---|---|
| `Table` | Drift table definitions |
| `DataClass` | Drift data classes |
| `View` | Drift view definitions |

The check walks the full supertype chain via the element model — it is not a string
match on source text (Invariant 1).

#### 2. Annotation registry (`annotation:<name>`)

If the class carries one of these annotations:

| Annotation | Ecosystem |
|---|---|
| `@DriftDatabase` | Drift |
| `@DataClassName` | Drift |
| `@riverpod` | Riverpod (lowercase constant) |
| `@Riverpod` | Riverpod (class annotation) |
| `@freezed` | freezed |
| `@JsonSerializable` | json_serializable |

#### 3. Structural fallback (`fallback:part_generated`)

If both conditions hold:

1. The library declares a `part '*.g.dart'` or `part '*.freezed.dart'` directive.
2. The class itself binds a generated counterpart — it `extends _$X` or `with _$X`
   (the `_$`-prefixed convention used by freezed and Riverpod class-based notifiers).

The part directive alone is deliberately **not** sufficient. Plain hand-written
classes that merely share a file with a generated notifier must remain candidates
(no over-suppression). The class must also bind the `_$`-symbol directly.

### What stays reported

Plain classes, utilities, and any class that matches none of the three signals above
remain candidates for the `unused-public-exports` rule. The suppression is targeted —
it only applies where the generator actually consumes the members.

### Planned: user-driven suppression *(not yet available)*

A future sprint (roadmap phase 7) will add a `loam.yaml` configuration and
`// loam-ignore:` inline comment syntax for user-driven suppression of individual
Findings. That feature does not exist yet — do not add `// loam-ignore:` comments
expecting loam.dev to honour them. This guide will be updated with full how-to
documentation when the feature ships.

<!-- codegen-suppression:end -->

---

## Links

- [Root README](../README.md) — install, quick start, roadmap
- [PRD](./PRD.md) — founding specification
- [Architecture decisions](./adr/) — locked design choices
- [CONTEXT.md](../CONTEXT.md) — canonical vocabulary
- [getloam.dev](https://getloam.dev) — website
