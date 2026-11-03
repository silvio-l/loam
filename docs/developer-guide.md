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
baseline diffing. It is built from the rule, the file and a semantic anchor
(scope plus normalised content), never from line numbers or running
occurrence numbers, so inserting code before a finding does not change it;
only truly identical findings in the same scope are told apart by order.
`ruleId` identifies which Rule produced it; `severity` is one of
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
| `a11y-form-field-label` | Flutter `TextField` and `TextFormField` without a visible or accessible label — neither `decoration: InputDecoration(labelText: …)` / `InputDecoration(label: Text(…))` nor `InputDecoration(hintText: …)` (accepted as a weaker fallback) nor an enclosing `Semantics(label: …)` ancestor. WCAG 1.3.1 Info and Relationships / 3.3.2 Labels or Instructions / 4.1.2 Name, Role, Value. Uses the resolved element model; local classes named `TextField` are never flagged. Conservative: a `decoration:` that is not a literal `InputDecoration(…)` creation is left alone. AST-only: out of scope are runtime contrast, focus order, touch-target sizes, and dynamic decoration values. |
| `a11y-icon-button-label` | Flutter `IconButton` without a `tooltip:` argument, without an `Icon(…, semanticLabel: …)` and without an enclosing `Semantics(label: …)` or `Tooltip(message: …)`, and `GestureDetector`/`InkWell` whose direct `child:` argument is a pure `Icon` and that likewise lacks such a name — WCAG 4.1.2 Name, Role, Value. Uses the resolved element model; local classes named `IconButton` are never flagged. AST-only: out of scope are composite icon children, dynamic tooltip values, and custom accessible-name mechanisms. |
| `a11y-image-label` | Flutter `Image` widgets (`Image()`, `Image.asset`, `Image.network`, `Image.file`, `Image.memory`) without `semanticLabel`, `excludeFromSemantics: true`, or an enclosing `Semantics(label: …)` / `Semantics(excludeSemantics: true)` / `ExcludeSemantics` (dot-shorthand images included) — WCAG 1.1.1 Non-text Content. Uses the resolved element model to identify Flutter's `Image`, not regex. AST-only: out of scope are runtime contrast, focus order, and touch-target sizes. |
| `a11y-interactive-semantics` | Generic and custom (non-Flutter) interactive widgets that carry an `onTap`, `onPressed`, or `onLongPress` named argument but lack both an enclosing `Semantics(label: …)` ancestor and a non-empty `label: …` / `semanticLabel: …` / `tooltip: …` argument on the call site itself — WCAG 4.1.2 Name, Role, Value. Project-defined wrapper widgets (a class with a build method, or a createState returning a State with one) are read via the element model: a name reaching Semantics(label: …), Tooltip, a label / semanticLabel / tooltip argument of a Flutter widget, a Flutter Text inside an interactive element of the wrapper (a Text beside an unnamed icon button names nothing) or another wrapper (up to four levels, each class analysed once) counts. A sink independent of the wrapper's fields labels the wrapper itself; a sink fed by fields requires the call site to pass the matching constructor argument, whatever its name. A wrapper that never routes a name to such a sink is reported once, at its class declaration, however often it is used (a wrapper that only forwards to it is not reported again; wrappers that build each other are reported once, at the one whose library URI and class name sort first); a call that omits the name of a wrapper that does route one is still reported at the call site. Fields handed to helper methods, to a widget inside the wrapper's tapped area, or to unreadable widgets make the analysis inconclusive; for such widgets (third-party, no build method) the call-site check on a non-empty label / semanticLabel / tooltip argument still applies. Flutter built-in interactive widgets covered by sibling rules (`IconButton`, `GestureDetector`, `InkWell`, `TextField`, `TextFormField`) are excluded. Uses the resolved element model (library URI check); local classes with the same name as excluded Flutter widgets are never skipped. AST-only: out of scope are interactive behaviour via inherited callbacks, custom gesture recognisers that bypass the named parameters, and accessible-name mechanisms other than `Semantics(label: …)` and the three recognised call-site properties. |
| `architecture-boundaries` | Imports that cross a forbidden layer boundary from `layers:` / `boundaries:` in `loam.yaml` — one finding per forbidden file-to-file edge at the import line, naming importing layer, target layer and both files. Reads only the configured architecture (never detects layers itself); no boundaries configured, no findings. Suppress with `// loam-ignore: architecture-boundaries – <reason>`. |
| `circular-dependencies` | Circular import/export chains between first-party `lib/` libraries — one finding per strongly connected component, naming all files in the loop. |
| `code-duplicates` | Structurally identical code blocks over the resolved AST (token-normalised, Rabin-Karp clustered); detects Type-1 (exact) and Type-2 (renamed identifiers/literals) duplicates project-wide. One finding per cluster listing all locations, with a stable fingerprint that survives line shifts. |
| `complexity-hotspots` | Cyclomatic and cognitive complexity per executable (function, method, constructor, accessor); flags hotspots above documented, conservative thresholds. Aggregated by `loam health` (together with project-wide finding load) into a composite Health-Score (0–100) and Grade (A–F). |
| `hardcoded-secrets` | API keys, passwords and tokens written into string literals. Two paths: (1) known provider formats anywhere in a literal (AWS access key id, GitHub token, Stripe live secret key, Google API key, Slack token, Anthropic/OpenAI key, PEM private key with a key body) — severity: error; (2) a literal on a credential-named site (variable, named argument, assignment target or map key such as password, apiKey, clientSecret, authToken) whose value is at least 8 characters, whitespace-free, not a placeholder and passes an entropy check — severity: warning. Category: slop. The value is never echoed: message, report, baseline and fingerprint carry only the site name or provider label. Fix: read the credential at runtime (`String.fromEnvironment`, `Platform.environment`, secret store) and rotate it if it was committed. What it deliberately does NOT catch: placeholders and samples (changeme, your-key, example, angle-bracket tokens), env-var names (`API_KEY`), storage-key names (`'auth_token'`), env reads and fallbacks (`a ?? 'x'`), interpolated strings, test/fixture/`example/` code, generated files and `firebase_options.dart`. |
| `slop-assertion-free-test` | A `test(…)` or `testWidgets(…)` (resolved to `package:test` / `flutter_test`, also inside `group(…)`) whose body never asserts: no `expect(…)`, `expectLater(…)`, `fail(…)`, `markTestSkipped(…)`, `expectAsync*`, `verify*` (mockito/mocktail), `check(…)` (`package:checks`), assert statement or throw in the body — neither directly nor in a project function it calls (resolved in the loaded files, up to 3 hops, cycle-safe). The test name claims a behaviour that nothing checks. Calls into other packages (`tester.pumpWidget`, …) are not assertions; a call of a function-typed parameter, field or variable counts as one, because the check lives where the callback is supplied (test wrappers like `appTest(name, body)`). Severity: info. Category: slop. Profile: strict. Not flagged: tests with a `skip:` argument and generated files. If the point is "does not throw", write `expect(() => …, returnsNormally)`; a project helper that asserts under another name goes under `slop_assertion_free_test.assertion_functions` in `loam.yaml`. Tests are only checked when they are not ignored (the `test/**` glob in `ignore:` excludes them). |
| `slop-empty-catch` | catch blocks whose body is empty (`{}`) or contains only comments — both silently swallow exceptions. Severity: warning. Category: slop. The official `empty_catches` lint already covers the literal `{}`; loam adds the comment-only variant that AI agents commonly produce and the project-wide gate. `catch (_) {}` with a literally empty body is the deliberate way to ignore an error and is not flagged. Conservative allowlist: any rethrow, throw, or logging call in the body suppresses the finding (all produce at least one statement). Generated files are skipped automatically. What it deliberately does NOT catch: bodies with any non-comment statement (rethrow, throw, logging call, or any other executable code). |
| `slop-unjustified-ignore` | `// ignore:` and `// ignore_for_file:` directives with no written justification — either inline (text after the lint names, separated by ` – ` or similar) or on the immediately preceding comment line. Severity: info. Category: slop. Generated files (.g.dart, .freezed.dart, etc.) are skipped automatically. What it deliberately does NOT catch: directives that have any non-empty text after the lint-name list (inline reason), directives whose preceding line contains any `//` comment (accepted as a reason), and directives in generated files. |
| `slop-narrative-comment` | `//` comments that add no information beyond what the code already shows. Declaration-adjacent: immediately before a declaration, normalised text restates the declaration name (e.g. `// build` before `void build()`) or belongs to a fixed restatement list ("constructor", "getter", "setter", "build method") or `the <name> method/widget` patterns. Context-free (anywhere in the file): decorative banner/divider comments (`// ====`, `// ****** SECTION ******`), bare structural category labels ("main logic", "helper function", "error handling", …), emoji-only decoration, redundant end-of-block markers (`// end if`, `// End processOrder`), and vague TODOs with no concrete action, condition, or reference (a TODO with real substance, e.g. `// TODO: handle null case when userId is missing (see #123)`, is never flagged). Severity: info. Category: slop. Generated files (.g.dart, .freezed.dart, etc.) are skipped automatically. What it deliberately does NOT catch: `///` Dart-doc comments (never flagged), block comments, plain hyphen dividers (`// ---------------`) — a common, legitimate section-separator convention, not AI-slop — and `//` comments with informative text that does not match any of the fixed categories above (no fuzzy heuristic quality scoring). |
| `slop-placeholder-comment` | A `//` or `/* */` comment whose **whole text** is a stand-in for code that is not there: `// ... rest of code`, `// ... existing code ...`, `// ... other methods`, `// rest of the implementation here`, `// existing code remains unchanged`, `// your code here`, `// add implementation here`. The visible trace of a truncated AI edit. Severity: warning. Category: slop. Profile: strict. Not flagged: `///` doc comments, a bare `// ...`, and any longer sentence that merely mentions the rest of the code. Generated files are skipped. |
| `slop-setstate-after-async-gap` | setState(…) calls resolved to Flutter's State.setState (package:flutter, never by name), on this/super or without a target, that can run after the state was unmounted: after an await (or await for) in an earlier statement of the same or an enclosing block, after an await in an enclosing if/while/?: condition, in catch/finally of a try whose body awaits, or in a callback passed to Future.then/whenComplete/catchError. A mounted check in between ends the search: an earlier if (…mounted…) return; (or throw/break/continue, also as a block) and an enclosing if (mounted …), mounted ? … : … or mounted && …; context.mounted counts too. Severity: warning. Category: slop. Profile: strict. Deliberately conservative — not reported: an earlier statement that both awaits and checks mounted, a branch that awaits and then always returns, calls inside other closures (forEach, Future.delayed, listeners, post-frame callbacks), awaits on an earlier loop iteration, tear-offs passed to then, and projects' own wrappers (safeSetState) or setState overrides. The guard analysis follows the idea of the official use_build_context_synchronously lint, which covers BuildContext but not setState. Needs the resolved element model, so it is not part of the parse-only loam slop fast path. |
| `slop-tautological-assertion` | expect/expectLater calls (resolved to package:test, flutter_test or matcher) that cannot fail: a constant literal — true, 1, 'a', null, or a collection/record literal made only of constants — against a literal, equals(<constant>) or one of isTrue/isFalse/isNull/isNotNull/isEmpty/isNotEmpty, or the same variable compared with itself (expect(x, x), expect(x, equals(x))). Severity: warning. Category: slop. Profile: core. Not reported: collection literals with identifiers, for/if elements or spreads, records with identifiers, interpolated strings, repeated calls (expect(next(), next())) and expect(x, isTrue). Needs the resolved element model, so it is not part of the parse-only loam slop fast path. |
| `slop-unimplemented-stub` | A top-level function, method, getter or setter in a source directory (`lib/`, `bin/`; `source_dirs`) whose entire body is `throw UnimplementedError(…)`, matched by name on the parse tree. Severity: warning. Category: slop. Profile: strict. Not flagged: a throw among other statements (e.g. a `default:` branch), members of abstract or sealed classes and mixins (template methods), classes extending `PlatformInterface` (the Flutter plugin template; a chain that leaves the file counts when the first foreign superclass is named `…Platform` or the file imports a `…platform_interface` library), tests, tools and generated files. |
| `slop-undisposed-resource` | A field of a Flutter State subclass, or of a class that declares its own dispose(), that the class creates itself (field initializer, or an assignment in initState, a constructor or any other member, from an instance creation or a static factory such as Timer.periodic) and that dispose() never releases. The resolved field type must offer a no-argument dispose, close or cancel (own or inherited, looked up on the element model; OverlayPortalController has none and is never flagged). close/cancel count only when the Dart SDK or a third-party package declares them: Flutter's and the project's own controllers use them for state changes such as MenuController.close(). Released means: the field is referenced anywhere in dispose() or in a method of the class that dispose() calls or tears off, directly or transitively (direct call, list, loop, ?.). Not flagged: values from constructor parameters, widget.x, provider/ref/context lookups, fields that also receive a non-created value, static fields, late fields never assigned a created value. Severity: warning. Category: slop. Profile: strict. Generated files are skipped. |
| `slop-workflow-narration-comment` | Sequential "workflow narration": two or more `// Step 1: …`, `// Step 2: …`, `// First, …`, `// Next, …`, `// Then, …`, `// Finally, …` comments, each immediately preceding a statement in the same function/method/constructor body, that together narrate the body step-by-step even though the statements are already self-explanatory. A single such comment on its own is not flagged — only a sequence (2+) is. Severity: info. Category: slop. Generated files are skipped automatically. What it deliberately does NOT catch: `///` Dart-doc comments, block comments, a lone workflow-style comment with no sequence, and comments not immediately adjacent to the statement they narrate. |
| `unused-public-exports` | Public API members (classes, methods, getters/setters, fields, enums, typedefs) with no references anywhere in the project — on the resolved element model, not regex. |

The remaining rules in the planned target surface (more AI-slop rules) are still to come (🚧).

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

#### Rule profiles (`core` / `strict`)

A **profile** decides which rules may turn the gate red. Every rule still runs and
every finding is still recorded in `baseline.json`; the profile only filters the
*gate decision*. Findings of rules outside the active profile are shown as one
hint line and never change the exit code.

| Profile | Blocks | Rules |
|---|---|---|
| `core` (default) | rules with a near-zero false-positive rate | `circular-dependencies`, `architecture-boundaries`, `unused-public-exports`, `slop-empty-catch`, `slop-tautological-assertion`, `slop-unjustified-ignore`, `hardcoded-secrets` |
| `strict` | every rule | `core` plus `slop-narrative-comment`, `slop-workflow-narration-comment`, `slop-placeholder-comment`, `slop-setstate-after-async-gap`, `slop-unimplemented-stub`, `slop-undisposed-resource`, `slop-assertion-free-test`, `code-duplicates`, `complexity-hotspots`, `a11y-form-field-label`, `a11y-icon-button-label`, `a11y-image-label`, `a11y-interactive-semantics` |

Choose with `loam gate --profile strict` or `profile: strict` in `loam.yaml`; the
command line wins. Because the baseline and the `ruleset@…` hash do not depend on
the profile, switching never rewrites the baseline or triggers the ruleset-changed
warning. Upgrading from a loam without profiles keeps the gate green where only
`strict`-profile findings would have failed it — set `profile: strict` to keep the
old behaviour. The rule-to-profile mapping lives in one place,
`lib/src/rules/rule_profile.dart`.

### Reporter

A **Reporter** converts Findings into output. It is a pure renderer: it has no
influence on the gate decision or exit code (pure renderer).

Available formats: see [Output formats](#output-formats) below.

### Recommendation

A **Recommendation** is a curated, agent-addressed suggestion for how to avoid
an entire *class* of Finding going forward — distinct from a Finding, which
describes one concrete occurrence at a file/line. After a run with Findings,
loam.dev appends **exactly one** Recommendation per distinct fired `ruleId`
(deduplicated, even if that rule fired dozens of times), sorted
lexicographically for determinism. The block is not shown on a clean run (no
Findings ⇒ no empty-noise block).

Recommendations are **curated, not LLM-generated** — a hand-written,
versioned guidance corpus (`guidance@ver`, currently `guidance@v2`) keyed by
`ruleId`, with no LLM call in the scan/gate path (Invariant 2). The text is
addressed to the AI agent consuming loam.dev's output, and explicitly asks the
agent to propose the relevant recommendations to its user for their
persistent instructions (e.g. `CLAUDE.md`) — **loam.dev itself never writes to
user instructions**.

In `human`/`markdown`/`html` output the block renders as readable prose with
the agent instruction spelled out; in `json` it is a structured
`recommendations` array of `{ "ruleId": "...", "guidance": "..." }` entries,
omitted entirely (not emitted empty) when there are no recommendations.

<!-- concepts:end -->

---

## Reproducibility

<!-- reproducibility:start -->

loam.dev is deterministic by design:

> **Same code + same `ruleset@ver`** ⇒ **identical Findings.**

The `ruleset@ver` is stored in `baseline.json` and in SARIF/JSON output alongside
the tool version. When the ruleset version changes (a rule is added or its logic is
updated), the gate warns and suggests a baseline refresh; when such a gate turns
red it says that the new findings may come from the changed ruleset. There is no
silent rule-version drift.

**Version pin and auto-update.** Without a pin, loam updates itself in the
background (see the README, section *Updates*), and the first run on the new
version names the rules the update added or removed. For a byte-stable gate,
pin the version in `loam.yaml`:

```yaml
required_version: ">=0.1.15 <0.2.0"   # pub constraint, or an exact "0.1.15"
auto_update: false                    # optional: keep the notice, never install
```

A pinned project is never updated. When the running version is outside the
constraint, commands warn on stderr and `loam gate` stops with exit code `78`.
CI (`CI`, `GITHUB_ACTIONS`, `GITLAB_CI` and other common variables) and
`LOAM_OFFLINE` never check or install; `LOAM_NO_AUTO_UPDATE` is the machine-wide
counterpart of `auto_update: false`.

**Analyzer store.** The analyzer keeps its summaries of the SDK, the
dependencies and the project's own libraries in `.dart_tool/loam/analyzer/`
between runs, so a warm run resolves in about half the time. The analyzer keys
every entry by its own version and the content it was built from, so a stale
entry is never used and results are identical with and without the store. An
unreadable or corrupt entry is a miss. If the store cannot be created, the run
uses none; if a load with it fails, loam prints one line to stderr (the error
type), deletes the store and loads again without it. Each run writes through
its own temporary files, so parallel runs do not collide. After a run that
wrote to it the store is trimmed to 512 MB, least recently used files first,
down to three quarters of that. The limit applies per project root: every
analysed package and every git worktree has its own `.dart_tool/loam/`.
On Windows the analyzer does not wait for its pending writes
(`FileByteStore.flush` is a no-op there), so loam waits for them itself before
it trims the store and exits, at most one minute. Temporary files that an
interrupted run left behind are deleted after an hour. Switch the store off
with `--no-cache` or `cache: false`.

**Parse-only runs.** Rules whose findings depend only on the file itself
(`FileRule`: `hardcoded-secrets`, `slop-empty-catch`, `slop-narrative-comment`,
`slop-unjustified-ignore`, `slop-workflow-narration-comment`) read nothing but
its parsed syntax tree. When every active rule is one of them, as in
`loam slop` with the resolving slop rules switched off
(`slop-tautological-assertion`, `slop-undisposed-resource`,
`slop-assertion-free-test` and `slop-setstate-after-async-gap` read resolved
elements, so a default `loam slop` resolves), the project is parsed instead of resolved (`--timing` then shows a
`parse` phase instead of `resolve`). Suppressions and the suppression audit
work the same. Unlike a resolving run, files with semantic errors (an
unresolved import, an undefined name) are checked too; only syntax errors
exclude a file. As soon as one other rule is active, the whole project is
resolved.

For the LLM layer *(planned)*: `sha(code)+prompt@ver` keys the VerdictCache, so
even the LLM path is deterministic per code snapshot.

<!-- reproducibility:end -->

---

## Configuration & discovery

loam is Zero-Config: without a `loam.yaml` it works out of the box. To customise,
scaffold one with `loam init` (writes a commented `loam.yaml`, plus detected architecture layers, to the project
root; it never overwrites an existing file).

**Discovery.** loam looks for `loam.yaml` by walking **up** from the analysed
project root to — and including — the enclosing **git repository root** (the
directory holding `.git`), exactly like Dart's own `analysis_options.yaml`. So a
config at your repo root applies even when a sub-package is analysed. The walk is
deliberately **bounded at the git root**: a `loam.yaml` above the repository (e.g.
in `$HOME`) is never picked up, which keeps discovery repo-relative and
reproducible across machines and CI. With no git root, only `<projectRoot>/loam.yaml`
is read.

**Layering (monorepos).** Every `loam.yaml` on the way is merged farthest→nearest,
so the repo root provides shared defaults and a nearer (per-package) config builds
on top of it. Merge rules — nearer wins:

| Key | Merge behaviour |
|---|---|
| `rules` | merged per ruleId; the nearer value overrides |
| `ignore` | concatenated (farther first), de-duplicated, order preserved |
| `source_dirs` | scalar override; a layer that omits it inherits the farther value |
| `update_check`, `a11y`, `auto_update`, `required_version`, `profile`, `strict_baseline`, `cache` | scalar override; omitted → inherit |
| `layers`, `boundaries` | `layers` merge per name; `boundaries` merge per `from` (nearer wins) |
| `code_duplicates.boilerplate` | scalar override; omitted → inherit |
| `code_duplicates.boilerplate_methods`, `unused_public_exports.annotations`, `slop_assertion_free_test.assertion_functions` | lists are united across layers |

`ignore` globs are always matched **relative to the analysed project root**,
regardless of which layer declared them — a repo-root `ignore: ["**/*.g.dart"]`
therefore applies relative to each analysed package.

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

### Global options

```
--format <format>    Output format (default: human).
--max-findings <n>    Cap for --format agent (default 20; 0 = all).
--no-progress         Suppress the live progress bar.
--timing              Print time per phase and per rule to stderr.
--timeout <duration>  Abort a run that takes longer (default 10m; 0 = off). Exit 124.
--no-update-check     Skip the update check and the automatic update for this run.
--no-cache            Don't keep the analyzer's summary store in .dart_tool/loam/ (same results).
--version             Print version, install channel and path, then exit.
```

Available formats: `human` · `sarif` · `json` · `markdown` · `html` · `agent`.

**Live progress.** `scan`, `gate`, `baseline`, `slop`, `a11y`, and `health` all
show the same live loading/analysis progress bar in an interactive terminal.
It is automatically disabled outside a TTY and under CI (non-empty `CI` env
var) — never interferes with piped or machine-readable output. Silence it
explicitly with `--no-progress` or the `LOAM_NO_PROGRESS` environment
variable; progress never appears in structured output (`sarif`/`json`/
`markdown`/`html`) regardless.

### `loam scan`

Full audit: runs all active rules across the whole project, baseline-independent.
Use this to see every Finding regardless of what is in the baseline.

```bash
loam scan                              # current directory
loam scan -p /path/to/project          # explicit project root
loam scan --format json                # machine-readable output
```

Exit code `1` when any Findings are present; `0` when clean; `64` on a usage
error (e.g. an invalid `--staged`/`--since`/`--changed` combination); `124` when
the run exceeds the `--timeout` limit.

This is the **Vollaudit** command — start here to assess a new project before
freezing a baseline.

### `loam watch`

Watch mode for local iteration: runs the same full audit as `loam scan` once,
then re-runs it after every change to a Dart file (or to `pubspec.yaml`,
`analysis_options.yaml`, `loam.yaml`) and prints what changed. Leave it running
in a terminal beside your editor.

```bash
loam watch                             # current directory
loam watch -p /path/to/project         # explicit project root
loam watch --debounce 1000             # wait 1 s of quiet before a run (default 300 ms)
```

Each run analyses the **whole project**, so findings that depend on other files
(import graph, cycles, unused exports, duplicates) are never lost, and a run
after an edit gives exactly what `loam scan` would give for the same state. What
stays warm between runs is the analyzer's summary store in `.dart_tool/loam/`
(see `--no-cache`), which is what makes a run after a small edit fast. The first
run prints the full report; every later run prints one line (which files
changed, how many Findings now, how many are new or resolved) followed by the
new (`+`) and resolved (`-`) Findings.

```
loam watch: lib/a.dart changed -> 3 findings (+1 new, -0 resolved)
  + [circular-dependencies] lib/a.dart:1 circular dependency ...
```

A burst of saves becomes one run (see `--debounce`); changes during a run lead
to exactly one follow-up run. Edits to `loam.yaml` take effect on the next run.
A run that fails (for example a broken `loam.yaml`) is reported on stderr and the
watch keeps going; the next change retries. Only `--format human` is supported.
`--timeout` does not apply to `watch`. Output of loam itself (`baseline.json`, the
HTML report, `.dart_tool/`) never triggers a run.

Stop with Ctrl+C (SIGINT) or SIGTERM: a running analysis finishes, the watcher is
released and the exit code is `0`; a second signal exits at once. Exit code `64`
on a usage error (unsupported `--format`, `--debounce` outside 0-60000 ms), `78`
when the first run cannot start (configuration error, no Dart SDK).

### `loam baseline`

Show, write, update, or prune the baseline (`baseline.json`).

```bash
loam baseline                          # show current baseline findings
loam baseline --write                  # freeze current findings as baseline
loam baseline --update                 # refresh an existing baseline
loam baseline --prune                  # drop stale entries, take in nothing new
```

`--prune` removes baseline entries whose Finding no longer occurs (the gate's
"gefixt" count), always project-wide. It never adds Findings, keeps the file's
ruleset version and fingerprint scheme, rewrites `baseline.json` atomically and
cannot be combined with `--write`/`--update` (exit `64`). Exit `66` when
`baseline.json` is missing or unreadable (as in `loam gate`), otherwise `0`.

**Baseline onboarding flow** for an existing project:
1. `loam scan` — see everything
2. Fix or accept what you can
3. `loam baseline --write` — freeze the accepted state
4. `loam gate` in CI from now on

### `loam gate`

CI gate: evaluates current Findings against the baseline.

```bash
loam gate                              # ratchet mode (default): only new findings fail
loam gate --strict-baseline            # stale baseline entries also fail the gate
loam gate --absolute                   # absolute mode: all findings evaluated, threshold 0
loam gate --profile strict             # heuristic rules block too (default profile: core)
loam gate --format sarif               # SARIF output (CI code-scanning)
loam gate --staged                     # only files staged in git (pre-commit)
```

Exit code `1` when the gate fails; `0` when it passes; `64` on a usage error
(an unknown `--profile`, not a git repository with `--staged`, or
`--strict-baseline` together with `--absolute`); `66` when ratchet mode finds no
`baseline.json` (the gate could not run; run `loam baseline --write` first, or
use `--absolute`); `78` when `loam.yaml` pins `required_version` and the running
loam does not match, or sets an unknown `profile`; `124` when the run exceeds
the `--timeout` limit (default 10 minutes), which is not a gate failure. See
"Output formats" for all exit codes.

Prints a terse summary line:
```
loam gate: N neu, M eingefroren, K gefixt — grün.
```

In the human finding list each line carries a baseline column: `new` marks a
finding that is not in `baseline.json`, unmarked lines are frozen. JSON output
is unchanged; SARIF carries the same information as `baselineState`.

Fingerprints do not depend on line endings: a Windows checkout with
`core.autocrlf=true` (CRLF) matches a baseline written on macOS or Linux (LF).

When new findings come from rules outside the active profile, a second line
reports them as a hint (`loam gate: N Hinweise aus Rules außerhalb des Profils
core …`); they do not count in `N neu`.

**Stale baseline entries.** The `K gefixt` entries are stale: their Finding no
longer occurs, so the baseline would let it return unnoticed. Besides the count,
the gate lists them per rule on stderr and points to `loam baseline --prune`.
They only fail the gate in strict mode: `--strict-baseline` or
`strict_baseline: true` in `loam.yaml` (default off; `--no-strict-baseline`
overrides the config; not allowed with `--absolute`). With `--staged`,
`--since` or `--changed` only entries of the selected files count. Legacy
baselines (before `fingerprintScheme: 2`) are matched by rule, file and message
first, so only genuinely unmatched entries are stale.

#### Reporting only changed files

`loam scan` and `loam gate` accept one of three selectors that narrow the
**report and the gate** to files git lists as changed:

| Flag | Files |
|---|---|
| `--staged` | In the git index (`git diff --cached`). |
| `--since <ref>` | Changed between the merge base of `<ref>` and `HEAD`, plus uncommitted changes to tracked files (untracked files are not included). |
| `--changed` | Changed in the working copy against `HEAD`: staged, unstaged and untracked (not ignored) files. |

```bash
loam scan --changed
loam gate --since origin/main
```

How it behaves:

- **The analysis stays project-wide.** Cross-file rules (`unused-public-exports`,
  `circular-dependencies`, `code-duplicates`) need the whole graph; only the
  resulting Findings are filtered by `Finding.filePath`. A cross-file Finding
  that lands in an *unchanged* file is therefore not shown (for example an export
  that became unused because a changed file dropped its last use); a full
  `loam gate` in CI still catches it.
- **Baseline and gate.** In ratchet mode the diff against `baseline.json` is
  computed over the whole project and then narrowed to the selected files: only
  *new* Findings in those files fail the gate, and "fixed" counts only baseline
  entries of those files. `loam gate --absolute` evaluates the filtered Findings.
  `baseline --write/--update` are never narrowed.
- The selectors are mutually exclusive. Paths are project-relative POSIX paths
  (also when the project is a subdirectory of the repository); deleted files are
  ignored.
- Not a git repository, `git` missing, an unknown `--since` ref or combined
  selectors exit with **64**.
- Notice on stderr: `analysis is project-wide; reporting only the N changed files.`

pre-commit hook (`.git/hooks/pre-commit`; make it executable, `dart` must be on
the hook's `PATH`, and ratchet mode needs a committed `baseline.json`, otherwise
use `dart pub global run loam gate --absolute --staged`). `--staged` selects the files in the index,
but the analysis reads the working-copy content, so unstaged edits to a staged
file are analysed too:

```bash
#!/bin/sh
exec dart pub global run loam gate --staged
```

Prefer `dart pub global run loam` over bare `loam` in hooks and CI: the pub shim
lives in `$HOME/.pub-cache/bin` on macOS/Linux but in
`%LOCALAPPDATA%\Pub\Cache\bin` on Windows, so a `PATH` assumption breaks there,
whereas `dart` is on the `PATH` of every Dart/Flutter setup. loam does not ship
the hook itself; if `dart` is missing the shell says so, and the fix is to
install the Dart/Flutter SDK and run `dart pub global activate loam`.

### `loam health`

Composite Health-Score (0–100) and Grade (A–F) combining finding load
(severity-weighted, size-normalised) and complexity hotspots (weighed
absolutely, not diluted by function count), plus a descending Hotspot table
(file:line, symbol, cyclomatic, cognitive). The terminal output breaks the
score down into its Findings and Complexity contributions.

```bash
loam health                    # analyse current directory
loam health /path/to/project   # positional project root
loam health -p /path/to/proj   # --project-root override
```

Exit code: always 0 on a successful run (even with a low score — gating stays
`loam gate`). Exit 64 on a usage error (e.g. two positional arguments).

The health score is a diagnostic view: it always measures, regardless of whether
`complexity-hotspots` is disabled in `loam.yaml`. The codegen exclusion (generated
files excluded by the collector) stays active.

### `loam slop`

AI-slop audit: runs slop-category rules only across the whole project.

```bash
loam slop                          # analyse current directory
loam slop /path/to/project         # positional project root
loam slop -p /path/to/proj         # --project-root override
loam slop --format json            # machine-readable output
```

Exit code `1` when any slop Findings are present; `0` when clean.

The `slop` category is run-isolated from drift and accessibility categories —
`loam slop` only ever executes `slop`-category rules.

`loam scan` includes slop rules **default-on**. Currently active slop rules: eleven —
`hardcoded-secrets` (plaintext API keys, passwords and tokens in string literals), `slop-empty-catch` (empty and comment-only `catch` bodies that silently swallow
exceptions), `slop-unjustified-ignore` (`// ignore:` and `// ignore_for_file:`
without a written justification), `slop-narrative-comment` (`//` comments that
restate the declaration name or use a fixed narrative phrase, plus banner
comments, empty category labels, emoji-only decoration, end-of-block markers,
and vague TODOs), `slop-workflow-narration-comment` (sequential `Step 1:`/
`First,`/`Next,`/`Then,`/`Finally,` comments narrating a function body
step-by-step), `slop-placeholder-comment` (comments like `// ... rest of code`
standing in for missing code), `slop-unimplemented-stub` (functions whose
whole body is `throw UnimplementedError()`), `slop-tautological-assertion`
(`expect(true, isTrue)`-style assertions that cannot fail),
`slop-undisposed-resource` (controllers, timers and notifiers a `State` creates
but never releases in `dispose()`), `slop-assertion-free-test` (`test`/`testWidgets`
bodies that never assert anything), and `slop-setstate-after-async-gap`
(`setState` after an `await` with no `mounted` check). Further slop rules (dead guards, …) are planned.

### `loam a11y`

Accessibility audit: runs accessibility-category rules across the whole project.

```bash
loam a11y                          # analyse current directory
loam a11y /path/to/project         # positional project root
loam a11y -p /path/to/proj         # --project-root override
loam a11y --format json            # machine-readable output
```

Exit code `1` when any accessibility Findings are present; `0` when clean.

Accessibility rules target WCAG-relevant Flutter-widget patterns (missing semantic
labels, missing tooltips on icon buttons, missing labels on form fields, …). The
`a11y` category is run-isolated from drift and slop categories — `loam a11y` only
ever executes `accessibility`-category rules; drift and slop rules are not touched.

`loam scan` includes the accessibility category **default-on**. To exclude it:

```bash
loam scan --no-a11y                # skip all accessibility-category rules
```

Or add `a11y: false` to `loam.yaml` for a repo-wide default. Precedence:
`--no-a11y` (CLI) > `a11y: false` (loam.yaml) > default (on).

Four accessibility rules are currently active: `a11y-form-field-label` (WCAG
1.3.1 / 3.3.2 / 4.1.2), which flags Flutter `TextField` and `TextFormField`
widgets without a `decoration: InputDecoration(labelText: …)` (or `hintText`
fallback) and without an enclosing `Semantics(label: …)` ancestor;
`a11y-image-label` (WCAG 1.1.1 Non-text Content), which flags Flutter `Image`
widgets without `semanticLabel` or `excludeFromSemantics: true`;
`a11y-icon-button-label` (WCAG 4.1.2 Name, Role, Value), which flags
`IconButton` without `tooltip` and `GestureDetector`/`InkWell` with a pure
`Icon` child when no `Semantics(label: …)` ancestor provides an accessible
name; and `a11y-interactive-semantics` (WCAG 4.1.2 Name, Role, Value), which
flags generic and custom (non-Flutter) widgets that carry an `onTap`,
`onPressed`, or `onLongPress` callback but have no `Semantics(label: …)`
ancestor **and** no `label`, `semanticLabel`, or `tooltip` argument with a
non-empty value on the call site itself (the latter covers custom widgets
that encapsulate their own accessibility, e.g. by wrapping themselves in
`Semantics(label: …)` internally or delegating the value to an
already-excluded Flutter widget). See the "Currently active rules" table
above.

### `loam init`

Scaffold a `loam.yaml` configuration in the current project.

```bash
loam init                    # writes loam.yaml in the current directory
loam init -p /path/to/proj   # specify a different project root
```

If `loam.yaml` already exists, the command refuses to overwrite it and exits with
code 1 — no silent data loss. Delete or edit the file manually to replace it.

The generated `loam.yaml` includes commented examples for the `rules:`, `ignore:`,
`source_dirs:`, `code_duplicates:` and `unused_public_exports:` sections. The file
is valid and loadable as-is (all examples are YAML comments, so no rule toggles are
active until you uncomment them; only the detected `layers:`/`boundaries:` block
below is active).

#### `layers:` / `boundaries:` — architecture layers, written by `loam init`

On a project with a recognisable `lib/` structure, `loam init` also writes the
detected **Layers** and the **Boundaries** (forbidden edges) derived from them as
active, visible YAML:

```yaml
layers:
  core: lib/core
  features: lib/features
boundaries:
  - from: core
    deny: [features]
```

`layers` maps a layer name to a project-relative directory prefix (`./lib/core/` and
`lib\core` are read as `lib/core`; an absolute path, the project root itself, or one
outside the project is a config error); each `boundaries` entry lists the layers
`from` must not import. Detection runs **only**
in `loam init` and never on a normal run: what is in `loam.yaml` is exactly what
applies, so edit or delete it freely - loam never re-detects or overwrites it. Nested
configs merge `layers` per name and `boundaries` per `from` (nearer wins); a boundary
naming an unknown layer is a config error.

Detection is deliberately conservative (a missing layer beats a wrong one): only the
well-known directories directly under `lib/` (`core`, `common`, `shared`, `utils`,
`domain`, `models`, `entities`, `data`, `repositories`, `services`, `presentation`,
`ui`, `features`, `screens`, `pages`) containing Dart files count, and boundaries
are derived only in the downward direction (foundation must not import presentation;
domain must not import data or presentation; data must not import presentation). If no
boundary can be derived, nothing is written. The `architecture-boundaries` rule
reports every `import` that crosses a listed boundary (a file belongs to the layer
with the longest matching directory prefix; files outside all layers are ignored)
and reads only these entries, so removing a boundary stops its findings. It is in
the `core` profile because it fires only for a boundary the project wrote down.

#### `source_dirs:` — production-source scope for the complexity scan

`complexity-hotspots` and `loam health` measure the **universal** property of
function complexity, so they need to know which directories hold hand-written,
shipping code. By default they measure **`lib/` and `bin/`**. Override per project:

```yaml
source_dirs:
  - lib
  - bin
  # - tool      # widen to include dev scripts
  # - test      # widen to include tests (usually noisy — intentionally complex)
```

Rules of the road:

- **Generated files are always excluded** (`*.g.dart`, gen-l10n output, …),
  regardless of `source_dirs`.
- `test/`, `example/` and `tool/` are **off by default** — test matrices and demo
  code carry intentionally high (or low) complexity that would only add noise.
- `circular-dependencies` and `unused-public-exports` are inherently a `lib/`
  concept (entrypoints can't sit in an import cycle; "public API" means `lib/`)
  and are **not** affected by `source_dirs`.
- For finer control, suppress individual findings by path with `ignore:` globs or
  inline `// loam-ignore: <ruleId>` directives.

#### Intended patterns: boilerplate and reserved APIs

Deliberately uniform code should not need one suppression per spot.

**`code-duplicates` skips boilerplate methods.** Detection is structural (AST),
by name *and* form: `operator ==` (one parameter), getters `hashCode` and `props`,
`toString`/`toJson`/`toMap` without required parameters, `copyWith` with only
named parameters, and `fromJson`/`fromMap` as factory constructor or static
method with one parameter. A method that only shares the name (for example a
positional `copyWith`) is still compared. The serialisers (`toString`, `toJson`,
`toMap`, `fromJson`, `fromMap`) must also be plain field mapping: a body with a
loop or a `switch` statement carries real logic and is compared as usual
(collection `for`/`if` inside a literal is fine). Configure in `loam.yaml`:

```yaml
code_duplicates:
  boilerplate: true            # false = compare boilerplate too
  boilerplate_methods: [toXml] # extra names, matched by name only (additive)
```

**`unused-public-exports` respects intent annotations.** `@visibleForTesting`,
`@internal`, `@visibleForOverriding`, `@protected` (members) and any `@pragma`
are never reported. The dedicated marker is **`@pragma('loam:reserved')`**: it
needs no dependency (`pragma` is part of `dart:core`; the Dart toolchain ignores
unknown pragma names), unlike an annotation class that would force `package:meta`
or a loam package onto every user. Project-local annotations can be added:

```yaml
unused_public_exports:
  annotations: [Keep]   # @Keep / @Keep(...) marks a symbol as deliberately public
```

**`slop-assertion-free-test` knows your own assertion helpers.** A test counts as
asserting when it calls `expect`/`verify`/`check`/… itself or through a function
declared in the project (up to three hops). A helper that checks under another
name can be listed explicitly (matched by function name, wherever it is declared):

```yaml
slop_assertion_free_test:
  assertion_functions: [expectGolden]
```

Unknown keys in these three sections are config errors (exit 78), so a typo never
silently re-enables findings. All lists are united across layered `loam.yaml` files.

### `loam fix` *(coming soon)*

Apply mechanical fixes for Findings that have a safe auto-fix. Not yet implemented.

<!-- commands:end -->

---

## Output formats

<!-- formats:start -->

All formats are selected with the global `--format` flag and work with every command
that produces Finding output. With every format except `human` and `html`, stdout
carries only the report; the gate summary, hints and notes go to stderr, so
`loam gate --format json | jq` always parses. `loam gate` with `json` or `sarif`
prints an empty document when there are no findings.

| Format | Status | Use case |
|---|---|---|
| `human` | **Available** | Default. Human-readable terminal output with colour (when TTY). |
| `sarif` | **Available** | SARIF 2.1 JSON for CI code-scanning tools (GitHub, GitLab, …). |
| `json` | **Available** | Machine-readable JSON for agent/tooling integration. |
| `markdown` | **Available** | Markdown report for PR comments, docs embedding, LLM pipelines. |
| `agent` | **Available** | Compact list for agents and chat: highest impact first (severity, rule, path, line), capped by `--max-findings` (default 20, `0` = all). The last line says how many findings were left out and how to see all. Other formats ignore the cap. |
| `html` | **Available** | Self-contained HTML report (`loam-report.html` by default; override with `--output`), opened automatically in the browser on interactive runs. `--no-open` skips it; auto-off when piped or under CI. |

The **Reporter is a pure renderer** — format choice never affects exit codes or
gate decisions.

**SARIF.** `sarif` follows SARIF 2.1.0: `tool.driver.rules` lists every rule that
occurs (sorted by id, with `help` text and `defaultConfiguration.level`), each
result carries `ruleId`/`ruleIndex`, `level`, a location with region, and
`partialFingerprints.loamFingerprint/v1` — the same position-robust fingerprint
as the baseline, so code-scanning systems recognise a finding across runs. In
`loam gate` (ratchet mode) each result also has `baselineState` (`new` or
`unchanged`), and baseline entries that no longer occur appear as `absent`.

**Exit codes.** `0` clean or gate green (or `loam watch` stopped by a signal) · `1` findings present (`scan`, `slop`,
`a11y`), gate red, or `loam watch` stopped because it could not write its output · `64` usage error (bad flag or `--max-findings` value) ·
`66` `loam gate` or `loam baseline --prune` found no `baseline.json` (it could
not run; not a red gate) · `78` configuration error (`loam.yaml`, version pin,
no Dart SDK) · `124` the run exceeded `--timeout`. Any other non-zero code is an unexpected crash.

**Fix-Prompt (`html` report).** The HTML report lets you select Findings and
copy a versioned Fix-Prompt (`prompt@v3`) for an AI coding agent. The prompt
names the analysed project via a stable, checkout-independent identifier (no
absolute path), scopes the agent to that project's own source tree, and
structures its instructions along four principles: think first (state
assumptions, ask instead of guessing), simplicity first (smallest fix, no
speculative abstraction), surgical changes (touch only what the Finding
requires, preserve existing style), and goal-driven (one verifiable success
criterion per Finding). The Dart template and the report's inline JS build
byte-identical prompts (single source of truth, Invariant 5).

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

<!-- codegen-suppression:end -->

---

## User-driven suppression

<!-- user-suppression:start -->

Three complementary mechanisms let you suppress Findings intentionally.
All three act **before** the baseline and gate — suppressed Findings are invisible
to the gate and do not appear in output or `baseline.json`.

### 1. Rule toggles (`loam.yaml` — `rules:` map)

Disable a rule project-wide in `loam.yaml`:

```yaml
rules:
  unused-public-exports: false   # rule is disabled; its findings are never produced
```

- A disabled rule is **not run** at all (no findings, no gate cost).
- Disabling a rule changes the `rulesetVersion` (the gate warns and suggests a
  baseline refresh — Invariant 5).
- An unknown `ruleId` raises a clear error on startup (`ConfigLoadException`) —
  no silent typo pass-through.

### 2. Path suppression (`loam.yaml` — `ignore:` glob list)

Exclude whole files or directories from the audit with project-relative glob
patterns:

```yaml
ignore:
  - "lib/generated/**"   # all files under lib/generated/
  - "**/*.g.dart"        # every .g.dart file anywhere in the project
```

- Matched files are **removed from the audit entirely** — no findings are produced
  for them, regardless of which rules are active.
- Path suppression does **not** change the `rulesetVersion` (it does not alter the
  rule set — only the scope of analysed files).
- Patterns are matched against project-relative POSIX paths (reproducible across
  platforms, Invariant 5).

### 3. Inline suppression (`// loam-ignore:` directive)

Suppress a single Finding for one specific rule at one specific location by
placing a `// loam-ignore:` comment **on the same line** as the flagged code or
on the **immediately preceding line**:

```dart
// loam-ignore: unused-public-exports – exported via barrel file, not direct ref
class MyPublicApi { … }

class AnotherClass { … }  // loam-ignore: unused-public-exports – plugin entry point
```

**Format:** `// loam-ignore: <ruleId> – <reason>`

- `<ruleId>` is the rule identifier (e.g. `unused-public-exports`).
- The reason is **mandatory** — a directive without a reason suppresses nothing
  (Grund-Pflicht) and is reported as a warning (see *Suppression audit* below).
- A separator between rule ID and reason is conventional (` – `, ` - `, or a
  space) but flexible; what matters is that non-empty text follows the rule ID.
- Only the **named rule** at the **named location** is suppressed; other findings
  of the same rule at different locations are not affected.
- This mechanism is **distinct from automatic codegen-input suppression** — the
  inline directive is user-authored and intentional, not derived from the element
  model.
- **Expiry (optional):** `// loam-ignore: <ruleId> until=YYYY-MM-DD – <reason>`
  keeps the directive active through that calendar day in the machine's local
  time zone. After it, the directive no longer suppresses (the finding comes
  back) and is reported as `expired`. `until=` must follow the rule id directly;
  inside the reason it is plain text and reported as `misplaced-expiry` (the
  directive stays valid but never expires). Results therefore depend on the date: a
  CI runner in UTC and a local machine can differ around midnight.

#### Suppression audit

Directives stay honest: `scan` and `gate` check them on every run and report
problems as **warnings**. Warnings never change the exit code and never enter
the baseline — only the findings themselves decide the gate.

| Kind | Meaning |
|---|---|
| `unused` | A valid directive that suppressed nothing — remove it. Only judged for rules that ran (`loam a11y` does not flag `slop-*` directives). |
| `expired` | The `until=` date has passed; the directive no longer suppresses. |
| `missing-reason` | Rule ID but no reason — suppresses nothing. |
| `missing-rule` | `// loam-ignore:` without a rule ID. |
| `invalid-expiry` | `until=` is not a real `YYYY-MM-DD` date — the directive is ignored. |
| `unknown-rule` | The rule ID does not exist. |
| `misplaced-expiry` | `until=` stands inside the reason, not directly after the rule ID — it never expires. |

A `loam-ignore` without a reason is reported only here, never also as
`slop-unjustified-ignore`: that rule judges Dart's own `// ignore:` comments,
not loam directives, so the two never overlap.

The report also shows how many findings each rule had suppressed
(`suppressed by rule: code-duplicates 12, unused-public-exports 3`; globs and
inline directives combined). `human` and `markdown` print both as plain lines,
`json` adds a `suppression` object (`byRule`, `notices`, and `evaluatedOn` — the
`YYYY-MM-DD` day expiry was judged against, present only when a directive has an
`until=`), `sarif` the same under
`runs[].properties.suppression`, and `html` shows the lines in the sidebar.
`loam gate` writes them to stderr, so stdout stays machine-readable. Expiry is
evaluated against the current date, so the same code can produce a different
result on a later day — that is the point of an expiry date.

### Scaffold via `loam init`

`loam init` writes a commented `loam.yaml` scaffold that illustrates all three
mechanisms. If `loam.yaml` already exists, the command refuses to overwrite it
(exit code 1) — no silent data loss.

<!-- user-suppression:end -->

---

## Links

- [Root README](../README.md) — install, quick start, roadmap
- [getloam.dev](https://getloam.dev) — website
