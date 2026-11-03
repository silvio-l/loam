# Changelog

## 0.1.16

- **The HTML report has the loam.dev look.** `loam scan --format html` now
  uses the website's brand: dark canvas, brand mark and `loam.dev` wordmark in
  the header, the project name as the title, and a clear order — Health-Score,
  counts by severity and by rule, findings with `file:line` in monospace, and
  the Fix-Prompt. Each finding now shows its remedy. The layout works from
  375 px phones up to ultrawide screens (sticky overview and Fix-Prompt
  columns, finding cards side by side on very wide screens) and respects
  reduced motion. The report stays one offline file and embeds no font: it
  uses the brand fonts when they are installed and system fonts otherwise.
- **New rule: `slop-undisposed-resource`.** Reports a field of a Flutter `State`
  (or of a class with its own `dispose()`) that the class creates itself - a
  `TextEditingController`, `FocusNode`, `ValueNotifier`, `Timer.periodic` and
  the like - but that `dispose()` never releases. The field's resolved type
  must offer `dispose`, `close` or `cancel` (`close`/`cancel` only from the Dart
  SDK or third-party packages, so `MenuController.close()` does not count);
  a release in `dispose()`, in a list or loop, with `?.` or in a helper method
  it calls counts as released. Values from parameters, `widget.x` or lookups
  are not reported. Part of the `strict` profile (warning); suppressible with
  `// loam-ignore: slop-undisposed-resource - <reason>` and baseline-able.
- **New rule `slop-assertion-free-test`** (profile `strict`, severity info):
  reports a `test(…)`/`testWidgets(…)` whose body never asserts — no
  `expect`, `expectLater`, `fail`, `verify*`, `check`, `expectAsync*`, `assert`
  or `throw`, neither in the body nor in a project function it calls (up to three
  hops). A call of a function-typed parameter or field counts as an assertion,
  so wrappers like `appTest(name, body)` are fine. Tests with `skip:` are ignored.
  Own assertion helpers go under `slop_assertion_free_test.assertion_functions`
  in `loam.yaml`.
- **Fix: fingerprints no longer depend on line endings.** Content anchors read
  multi-line string literals with their raw line breaks, so a CRLF checkout
  (Windows, `core.autocrlf=true`) gave findings around such strings other
  fingerprints than an LF checkout, and a baseline written on one system
  reported them as new on the other. Line breaks inside tokens are now read as
  LF; fingerprints of LF files do not change. The placeholder-comment message
  quotes block comments with LF breaks too.
- **`loam gate` marks new findings.** In the human output every finding line
  carries a baseline column: `new` for findings missing from `baseline.json`,
  blank for frozen ones, so a red ratchet names its cause. JSON and SARIF stay
  as they are (SARIF already has `baselineState`).
- **Fix: fewer false alarms from the three accessibility rules.**
  `a11y-icon-button-label` no longer reports an `IconButton` inside a
  `Tooltip(message: …)` or with an `Icon(…, semanticLabel: …)`;
  `a11y-image-label` no longer reports an image under `Semantics(label: …)`,
  `Semantics(excludeSemantics: true)` or `ExcludeSemantics`, and now also checks
  dot-shorthand images (`Image logo = .asset(…)`); `a11y-form-field-label`
  accepts `InputDecoration(label: Text(…))`. The remedies name these options,
  and the form-field remedy says `hintText` is only a fallback.
- **Fix: `unused-public-exports` no longer reports `toJson`, `toString`,
  `noSuchMethod` and `call`.** Dart's core libraries call these without a
  static call site (`jsonEncode(x)` runs `x.toJson()`), so a missing reference
  does not mean they are unused. Members of enums, mixins, extensions and
  extension types are now recognised as part of their own declaration, like
  class members.
- **Fix: `slop-empty-catch` accepts `catch (_) {}`.** The wildcard is Dart's
  marker for "ignored on purpose" (the official `empty_catches` lint agrees),
  so `catch (_) {}` and `on X catch (_) {}` with a literally empty body are no
  longer flagged. `catch (e) {}`, a wildcard with a comment in the body and
  `catch (_, st) {}` are still reported. The rule text now says plainly that
  the official `empty_catches` lint already covers the literal `{}` and that
  loam adds comment-only bodies and the project-wide gate.
- **Fix: `complexity-hotspots` counts the Dart 3 constructs modern code
  branches with.** Switch expressions (one point per arm, the `_` catch-all
  free), collection `if` / `for` elements in lists, maps and sets, `if (x case
  P when g)` conditions and `||` / `&&` patterns now add to cyclomatic and
  cognitive complexity by the same rules as their statement and operator
  counterparts (collection elements and switch expressions nest like
  `if` / `for` / `switch`). Complexity and the `loam health` score were too
  low for such code. The ruleset version changes (`ruleset@…`), and existing
  baselines may report new `complexity-hotspots` findings for functions that
  were just under a threshold: review them, then refreeze with
  `loam baseline --update`.
- **Fix: sharper findings in five rules.** `slop-unjustified-ignore` no longer
  reacts to `/// ignore:` doc comments or `// ignore:` text in strings, and now
  reports `// ignore: type=lint` without a reason. `hardcoded-secrets` finds
  credentials in parameter default values (`{this.password = '…'}`); Google
  `AIza…` keys are a warning that asks you to restrict the key, because
  Google treats such keys as client identifiers. `architecture-boundaries`
  documents that only imports are checked, not exports. `slop-unimplemented-stub`
  treats a `mixin class` like a mixin template. `slop-narrative-comment` flags
  a framed label only for a real frame (`=== LABEL ===`), no longer for
  comments such as `// __init__ … __dispose__` or `**Note** … **bold**`.
- **Fix: Windows runs keep their analyzer store and leave no temp files.** On
  Windows the analyzer's store flush does nothing, so a run that exited right
  away lost pending writes and left `*-temp-*` files behind. loam now waits for
  the pending writes (at most one minute) before it closes the store and
  removes temp files older than an hour. `loam watch` now reports changed files
  with forward slashes on Windows too.
- **Fix: the HTML report opens on Windows when its path contains `&` or `^`.**
  `--format html` started the browser through `cmd /c start`, which cut such
  a path at `&` and ran the rest as a command. It now hands the path to the
  Windows shell directly.
- **Fix: `--format json` and `--format sarif` keep stdout a pure document.**
  Summary lines and notes go to stderr for every machine-readable format, and
  `loam gate` prints an empty document when there are no findings, so the
  output can be piped straight into a parser.
- **New rule: `slop-setstate-after-async-gap`.** Reports `setState(…)` in a
  Flutter `State` that can run after the screen was closed: after an `await`
  (also inside `try`, or in `catch`/`finally` of an awaiting `try`), or in a
  `Future.then` / `whenComplete` / `catchError` callback, with no `mounted`
  check in between. `if (!mounted) return;`, `if (!context.mounted) return;`,
  `if (mounted) …` and `mounted ? … : …` count as guards. Only Flutter's
  `State.setState` counts, resolved on the element model; a project's own
  wrapper such as `safeSetState` is not reported. Unclear control flow is not
  reported either. Part of the `strict` profile (warning); suppressible with
  `// loam-ignore: slop-setstate-after-async-gap – <reason>` and
  baseline-able.
- **New rule: `slop-tautological-assertion`.** Reports `expect` / `expectLater`
  calls that cannot fail: a constant literal checked against a literal,
  `equals(<constant>)` or a constant matcher (`expect(true, isTrue)`,
  `expect(1, 1)`, `expect(null, isNull)`), or a value compared with itself
  (`expect(x, x)`). Only the `expect` from `package:test`, `flutter_test` or
  `matcher` counts, resolved on the element model. Collection literals with
  variables or `for` elements, records with identifiers and `expect(x, isTrue)`
  are not reported. Part of the `core` profile (warning); suppressible with
  `// loam-ignore: slop-tautological-assertion – <reason>` and baseline-able.
- **New rule: `architecture-boundaries`.** Reports `import` edges that cross a
  forbidden layer boundary from `layers:` / `boundaries:` in `loam.yaml`: one
  finding per forbidden file-to-file edge at the import line, naming the
  importing layer, the target layer and both files, with a remedy that says how
  to invert the dependency. It reads only the configured architecture and never
  detects layers itself, so without boundaries it reports nothing. Part of the
  `core` profile (it fires only for boundaries the project wrote down).
  Suppressible with `// loam-ignore: architecture-boundaries – <reason>` and
  baseline-able like any other rule. Layer directories may be written as
  `./lib/core/` or `lib\core`; an absolute path, the project root itself, or
  one outside the project is a config error.
- **`slop-unimplemented-stub`: no false alarm for a `PlatformInterface` chain
  across files.** A class whose `extends` chain leaves the file is now treated
  as a plugin platform interface when the first foreign superclass is named
  `…Platform` or the file imports a `…platform_interface` library. The rule
  stays on the parse path (no resolution); a missed stub is preferred over a
  false alarm.
- **`loam init` detects architecture layers and writes them to `loam.yaml`.**
  From the well-known directories under `lib/` (`core`, `domain`, `data`,
  `features` ...) it derives **Layers** and the forbidden **Boundaries** between
  them and writes both as visible `layers:` / `boundaries:` entries. Detection
  runs only in `init`; a normal run never re-detects, and an existing
  `loam.yaml` is never overwritten. With fewer than two layers or no derivable
  boundary nothing is written. The `architecture-boundaries` rule
  reports violations.
- **Suppression audit: evaluation date and misplaced `until=`.** The `suppression`
  object in JSON and SARIF gains `evaluatedOn` (`YYYY-MM-DD`, only when a
  `// loam-ignore:` directive has an expiry date), so a report states which day
  its expiry decisions were made on. An `until=` written inside the reason text
  (instead of directly after the rule ID) is now reported as the new notice
  kind `misplaced-expiry` rather than silently ignored; the directive stays valid.
- **`a11y-interactive-semantics` reports a swallowed name once, at the
  wrapper.** A project widget that never routes a name to
  `Semantics(label:)`, a tooltip or a `Text` inside its tapped area is now one
  finding at its class declaration, no matter how many call sites or forwarding
  wrappers use it; those call sites are no longer reported. A call that omits
  the name of a wrapper that does take one is still reported at the call. A
  `Text` next to an unnamed icon button no longer counts as its name, and a
  field handed to a widget inside the tapped area (`child:`) leaves the wrapper
  unjudged. The fingerprint is anchored on the wrapper name, so a baseline may
  list the old call-site entries as stale (`loam baseline --prune`).
  Wrappers that swallow the name and build each other are reported once (at
  the one whose library URI and class name sort first) instead of not at all.
- **Docs: platform-neutral hook and CI invocation.** The pre-commit recipe and
  the CI guidance now use `dart pub global run loam …`, which does not depend on
  where pub puts its shim (`%LOCALAPPDATA%\Pub\Cache\bin` on Windows,
  `~/.pub-cache/bin` elsewhere).
- **Two new slop rules.** `slop-placeholder-comment` flags a comment whose whole
  text stands in for missing code (`// ... rest of code`, `// ... existing code
  ...`, `// your code here`); longer prose that merely mentions the rest of the
  code is never flagged. `slop-unimplemented-stub` flags functions, methods,
  getters and setters in `lib/`/`bin/` whose entire body is `throw
  UnimplementedError()` (matched by name on the parse tree, so slop-only runs
  stay parse-only), except template members of
  abstract/sealed classes and mixins, `PlatformInterface` subclasses, tests and
  generated files. Both are `strict` profile, so they never block the default
  gate. The third rule planned in #14, TODO without a reference, is not part of
  this change (open product question, see #76).
- **Fix: member anchors name the class again (`Class.method`).** With the
  current analyzer AST the class body is its own node, so the owner lookup
  found nothing and findings in class members were anchored as just `method`;
  same-named methods of different classes in one file shared a scope. Affects
  the `a11y-*` rules and `slop-empty-catch`. **Fingerprints of findings inside
  class, mixin, enum, extension and extension type members change once.** Existing baselines
  report them as new plus stale: refresh the baseline with
  `loam baseline --update` to adopt the new anchors. Top-level
  functions are unaffected.
- **New command: `loam watch` for local iteration.** Runs the full audit once,
  then again after every change to a Dart file, `pubspec.yaml`,
  `analysis_options.yaml` or `loam.yaml`, and prints what is new (`+`) and
  resolved (`-`). Every run analyses the whole project on top of the persistent
  analyzer store, so cross-file findings (cycles, unused exports, duplicates)
  match a full `loam scan`. Bursts of saves become one run (`--debounce`,
  default 300 ms). SIGINT/SIGTERM end it cleanly with exit 0; `--timeout` does
  not apply. Human output only. Changed files are named with `/` on every
  platform.

- **Stale baseline entries are reported and can be removed.** `loam gate`
  (ratchet) names baseline entries whose finding no longer occurs, per rule, on
  stderr (the "gefixt" count). `loam baseline --prune` removes exactly those
  entries: it takes in nothing new, keeps the ruleset version and fingerprint
  scheme of the file and replaces `baseline.json` atomically. `loam gate
  --strict-baseline` (or `strict_baseline: true` in `loam.yaml`; the flag
  overrides, `--no-strict-baseline` turns it off) makes stale entries turn the
  gate red, so CI can force the cleanup. With `--staged`/`--since`/`--changed`
  only entries of the selected files count; `--prune` is always project-wide and
  rejects `--write`/`--update`.

- **Fix: test suite no longer needs a manual `pub get` per fixture.** Ten test
  files (circular dependencies, import graph, public API collector, unused
  public exports, agent-proof contract, project loader, complexity collector,
  progress sink, suppression audit) failed with `LoadFileError` on any
  fresh checkout, first seen on Windows, because the gitignored
  `package_config.json` of their fixture packages was missing. They now resolve
  the fixture themselves (`test/support/fixture_packages.dart`). Tests only.
- **Fix: self-update locks have exactly one owner.** The state and worker locks
  are now operating-system file locks (macOS, Linux, Windows) instead of a lock
  file with a timestamp. Two runs can no longer both take an expired lock, and
  a crashed run frees its lock by itself.
- **Faster resolving with a persistent analyzer store.** The analyzer keeps
  its summaries of the SDK, the dependencies and the project's libraries in
  `.dart_tool/loam/analyzer/` between runs, which roughly halves the resolve
  phase on a warm store. Results are identical with and without it; a
  damaged store is ignored, and if loading with it fails loam says so on
  stderr, deletes it and continues without it. The store is trimmed to 512 MB
  per project root (least recently used entries first). Switch it off with
  `--no-cache` or `cache: false` in `loam.yaml`.
- **`loam slop` only parses.** When every active rule reads nothing but the
  file itself (`hardcoded-secrets` and the four `slop-*` rules, e.g.
  `loam slop` or a config that leaves only those), the project is parsed
  instead of resolved, which takes a fraction of the time. Inline suppressions
  and their audit work as before. Behaviour change: in such runs files with
  semantic errors (an unresolved import, an undefined name) are now checked
  too; only syntax errors still exclude a file.
- **Intended patterns are no longer reported.** `code-duplicates` skips
  boilerplate methods (`copyWith`, `==`, `hashCode`, `toString`, `toJson`/
  `toMap`, `fromJson`/`fromMap`, equatable `props`), recognised by name and
  form; `unused-public-exports` also respects `@protected`, the dependency-free
  marker `@pragma('loam:reserved')` and project annotations. Configure via the
  new `code_duplicates:` (`boilerplate`, `boilerplate_methods`) and
  `unused_public_exports:` (`annotations`) sections in `loam.yaml`.
- **`--timing`.** Any analysing command prints wall-clock time per phase
  (setup, resolve or parse, rules, suppression, update-check; report for `scan`) and per
  rule to stderr, so a slow run shows where the time goes. stdout is unchanged.
- **Fix: fingerprints no longer depend on running numbers (new fingerprint
  scheme 2).** `slop-empty-catch`, `slop-unjustified-ignore` and the
  `a11y-form-field-label`, `a11y-icon-button-label`, `a11y-interactive-semantics`
  and `a11y-image-label` rules used an occurrence counter as anchor, so adding
  or removing one finding turned every later finding of that kind into a "new"
  one and forced baseline refreshes. The anchor is now the scope plus the
  normalised content of the flagged construct (formatting, comments and closure
  bodies do not count); a counter only separates truly identical findings in
  the same scope. Scope detection now also covers mixins, enums, extensions and
  extension types. **Migration:** `baseline.json` records `fingerprintScheme: 2`.
  An older baseline keeps working: findings whose fingerprint changed are
  matched to baseline entries by rule, file and message, so the gate stays
  green and prints a one-time note. Run `loam baseline --update` once to
  upgrade the file.
- **Suppressions are now auditable.** `// loam-ignore:` directives that
  suppress nothing (`unused`), have no reason or rule ID, name an unknown rule,
  or carry an invalid or expired date are reported as warnings by `scan` and
  `gate`, instead of being dropped silently. A directive can carry an optional
  expiry, `// loam-ignore: <ruleId> until=YYYY-MM-DD – reason`; after that day it
  stops suppressing and the finding returns. Reports show how many findings each
  rule had suppressed (`json`/`sarif` get a `suppression` object). The warnings
  never change the exit code and never enter the baseline: only findings decide
  the gate.
- **A run never hangs silently: `--timeout`.** `loam` now aborts a run that
  takes longer than 10 minutes (override with `--timeout <duration>` or
  `LOAM_TIMEOUT`, e.g. `90s`, `30m`, `1h`; `0`/`off` disables it). The message
  on stderr names the phase and rule that was running and how to raise the
  limit; the exit code is `124` (distinct from `1` findings, `64` usage, `78`
  config), so a hook can tell a timeout from a red gate. stdout stays clean.
  Raised after a `loam gate` hung in a pre-commit hook under high load.
- **Only report changed files: `--staged`, `--since <ref>`, `--changed`.**
  `loam scan` and `loam gate` can narrow report and gate to the files git lists
  as changed, for example as a pre-commit hook (`loam gate --staged`) or a PR
  check (`loam gate --since origin/main`). The analysis stays project-wide so
  cross-file rules keep their full context; in ratchet mode the baseline diff is
  computed project-wide first, so unchanged files are never counted as fixed.
  Outside a git repository or with an unknown ref, loam exits with 64.
- **`a11y-interactive-semantics` reads your own wrapper widgets.** A widget
  defined in the project whose `build()` routes a name to `Semantics(label:)`,
  a `Tooltip`, a `label`/`semanticLabel`/`tooltip` argument or a `Text` (also
  through further wrappers, up to four levels, each class analysed once) is
  accepted at its call sites, whatever the parameter is called. A wrapper that
  swallows its label is still reported, even when the call site passes
  `label:`. Wrappers that cannot be read keep the call-site check.
- **Rule profiles: `core` blocks, `strict` is opt-in.** `loam gate` now blocks
  only on rules of the active profile. `core` (default) holds the rules with a
  near-zero false-positive rate: `circular-dependencies`,
  `unused-public-exports`, `slop-empty-catch`, `slop-unjustified-ignore`,
  `hardcoded-secrets`. `strict` adds the heuristic and threshold-based ones
  (comment slop, `code-duplicates`, `complexity-hotspots`, `a11y-*`). Findings
  of the other rules still run and appear as one hint line. Choose with
  `loam gate --profile strict` or `profile: strict` in `loam.yaml` (CLI wins;
  unknown value: exit 64 / 78). `baseline.json` and the `ruleset@…` hash do not
  depend on the profile. **Behaviour change:** a gate that only failed on
  `strict`-profile rules is now green; set `profile: strict` to keep the old
  behaviour. The website rules page shows the profile of each rule.
- **Compact output for agents, fuller SARIF, distinct exit code.** New
  `--format agent` lists the highest-impact findings first (severity, rule,
  path, line) and stops at `--max-findings` (default 20, `0` = all); the last
  line says how many were left out and how to see them all. Other formats are
  unchanged and always list everything. SARIF now carries `rules` with help
  text, `ruleIndex`, `partialFingerprints` (the baseline fingerprint) and, in
  `loam gate`, `baselineState` (`new`, `unchanged`, and `absent` for fixed
  entries). `loam gate` without a `baseline.json` now exits 66 instead of 1, so
  CI can tell "could not run" from "gate red". Exit codes are documented in the
  developer guide.
- **Fix: `// loam-ignore:` works on Windows.** Eight rules (`a11y-*` and
  `slop-*`) reported finding paths with backslashes on Windows, while inline
  directives and baseline entries use forward slashes. No inline suppression
  matched there, so suppressed findings failed the gate as new. All rules now
  report project-relative POSIX paths on every OS.
- **Auto-update, unless pinned.** The update check left the hot path: it runs
  at most once a day in a detached background process, and the next run
  reports the result. A `dart pub global activate` install and a standalone
  release binary now update themselves (the binary only after the archive
  matches the release's `.sha256`; releases now publish these files). Homebrew,
  source and git/path installs keep the notice with the right command. The
  first run after an update names the rules it added or removed, and a gate
  that turns red on a changed ruleset says so. New `loam.yaml` keys:
  `required_version` (pub constraint; never updated, `loam gate` stops with
  exit 78 on a mismatch) and `auto_update: false`; new environment variables
  `LOAM_NO_AUTO_UPDATE` and `LOAM_OFFLINE`. CI detection now covers common CI
  variables beyond `CI`/`GITHUB_ACTIONS`.
- **Fix: install channel of `dart pub global activate` installs.** loam ran as
  a snapshot under the Dart VM, so channel detection looked at the `dart`
  binary; with a Homebrew-installed Dart SDK a pub install was reported as
  Homebrew. Detection now uses the snapshot path; `loam --version` shows it.
- **New rule: `hardcoded-secrets` (slop).** Flags plaintext credentials in string
  literals, offline and without any value leaving the rule. Two paths: known
  provider formats anywhere (AWS access key id, GitHub, Stripe live, Google API,
  Slack, Anthropic and OpenAI keys, PEM private keys with a key body; severity
  error) and credential-named sites (`password`, `apiKey`, `clientSecret`,
  `authToken`, ... as variable, named argument, assignment or map key) holding a
  high-entropy value (severity warning). Placeholders, env-var and storage-key
  names, `String.fromEnvironment` / `Platform.environment` reads, tests,
  fixtures, `example/`, generated files and `firebase_options.dart` are not
  reported. The value never appears in messages, reports, baseline or
  fingerprint; suppress with `// loam-ignore: hardcoded-secrets - <reason>`.
- **Fix: `code-duplicates` fingerprints are now truly position-robust.** The
  fingerprint used to include the start line of every copy, so adding a line
  above a duplicated block (for example a new field in a settings file) turned
  an existing finding into a "new" one and failed the gate. The fingerprint is
  now built from the clone's identity instead: the token count, a SHA-256 of the
  normalised token sequence, and the occurrence file paths. Line shifts keep a
  finding in `keptFindings`; adding or removing a copy still changes it.
  **Migration (once):** the fingerprints of existing `code-duplicates` findings
  change, so the first `loam gate` after upgrading reports them as new. Refresh
  the baseline once with `loam baseline --update` and commit `baseline.json`.
  The `rulesetVersion` does not change (it hashes rule IDs only), so the gate
  does not print its refresh hint in this case.

## 0.1.15

- **Maintenance: dependency and CI upkeep, no rule/behavior changes.** Bumped
  `analyzer` to 14.3.0 (constraint widened, lockfile re-resolved), grouped
  `pub`/`npm` minor/patch dependency updates, and `web-vitals`/`vitest` majors
  verified compatible. Pinned the CI Dart SDK to the version the repo is
  actually formatted with, fixing recurring `dart format` CI failures caused
  by the `stable` channel drifting ahead of the repo's formatting.

## 0.1.14

- **Fix: `a11y-interactive-semantics` no longer flags custom widgets that
  already carry their own accessible name.** The rule previously suppressed a
  finding only when the call site was wrapped in a `Semantics(label: …)`
  ancestor — it never inspected the call site's own arguments. Two
  independent field reports (a widget that wraps itself in `Semantics(...)`
  internally, and a widget that delegates its label transitively to an
  already-excluded Flutter button) both turned out to pass their accessible
  name through a `label:` argument on the call site itself. The rule now also
  accepts a non-empty `label`, `semanticLabel`, or `tooltip` named argument on
  the call site as a sufficient accessible name, covering both shapes without
  opening the target class's definition. An empty string (`''`) or `null`
  still does not count — the rule stays conservative.

## 0.1.13

- **Fix: `ignore` globs and the gate now suppress correctly no matter which
  directory you run loam from.** Path-based suppression matched the ignore
  globs against a path that was accidentally resolved relative to the current
  working directory, so running loam from a directory other than the analysed
  project root — e.g. `loam gate --project-root packages/app` from a repo root,
  or any CI job whose working directory differs from `--project-root` — silently
  dropped all `ignore`-glob suppressions. Findings you had deliberately excluded
  could reappear and fail the gate. Suppression is now matched against each
  finding's project-relative path directly and is independent of the process
  working directory. Inline `// loam-ignore:` suppression was unaffected.

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
