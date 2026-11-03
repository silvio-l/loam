import '../architecture/layer_detector.dart';

/// Generates a commented, annotated `loam.yaml` scaffold as a pure String.
///
/// [ConfigScaffold] has **no I/O** — it returns a deterministic String that
/// the caller (e.g. `loam init`) is responsible for writing to disk.
///
/// The generated content mirrors the schema accepted by [ConfigLoader]:
/// - `rules:` — ruleId → bool toggle map (example entries are YAML comments
///   so the file loads cleanly via [ConfigLoader] without triggering the
///   unknown-ruleId guard; active toggles reference only real registry IDs).
/// - `ignore:` — list of project-relative glob patterns.
/// - `layers:` / `boundaries:` — only when a [DetectedArchitecture] is passed
///   to [generate]; active (not commented) so the detection is visible.
///
/// **Design decision:** example rule toggles are shipped as YAML comments, not
/// active entries. This guarantees that the generated file is always valid as-is
/// (no ConfigLoadException on first load), while still showing users the syntax.
/// Any real ruleId used in active (non-comment) entries must exist in the
/// registry at the time of generation — currently that is `unused-public-exports`.
abstract final class ConfigScaffold {
  /// Returns the canonical, deterministic scaffold content for `loam.yaml`.
  ///
  /// The returned string:
  /// - Ends with a single trailing newline (`\n`).
  /// - Is POSIX line-ending only (`\n`, never `\r\n`).
  /// - Is identical across calls and platforms (Invariant 5 / reproducibility).
  static String generate({DetectedArchitecture? architecture}) {
    if (architecture == null || architecture.isEmpty) return _content;
    return '$_content${_architectureBlock(architecture)}';
  }

  /// The visible, active `layers:` / `boundaries:` block that `loam init`
  /// materialises from [LayerDetector]. Plain YAML the user can edit or delete;
  /// loam never rewrites it on later runs.
  static String _architectureBlock(DetectedArchitecture a) {
    final b = StringBuffer('''
# ---------------------------------------------------------------------------
# layers / boundaries — architecture layers and the edges between them
#
# Detected by `loam init` from your lib/ directory structure and written here
# so you can see, edit or delete them. loam never re-detects or overwrites
# this block on later runs — what is below is exactly what applies.
#
# layers:     layer name -> project-relative directory prefix
# boundaries: per importing layer (from), the layers it must not import (deny)
# ---------------------------------------------------------------------------
layers:
''');
    for (final e in a.layers.entries) {
      b.writeln('  ${e.key}: ${e.value}');
    }
    b.writeln('boundaries:');
    for (final bd in a.boundaries) {
      b.writeln('  - from: ${bd.from}');
      b.writeln('    deny: [${bd.deny.join(', ')}]');
    }
    return b.toString();
  }

  // ---------------------------------------------------------------------------
  // The scaffold content is a compile-time constant so it is guaranteed to be
  // identical on every call (no runtime mutation, no platform variance).
  // ---------------------------------------------------------------------------
  static const String _content = '''# loam.yaml — loam.dev configuration
#
# loam.dev: Codebase intelligence & anti-AI-slop for Dart/Flutter.
# CLI: loam  |  Docs: https://github.com/silvio-l/loam
#
# This file is optional — loam works out-of-the-box without it (Zero-Config).
# All options below are shown with their defaults; uncomment to override.
#
# Discovery: loam searches for loam.yaml by walking up from the analysed
# project root to the enclosing git repository root (like analysis_options.yaml).
# In a monorepo, a repo-root loam.yaml provides shared defaults and a nearer
# (per-package) loam.yaml layers on top of it (nearer wins; ignore lists are
# additive). See docs/developer-guide.md → "Configuration & discovery".
#
# Schema: https://github.com/silvio-l/loam (see internal-notes)

# ---------------------------------------------------------------------------
# update_check — opt out of the update-availability notice (bool, default true)
#
# true  = loam checks for a new version once per 24 h and prints a notice on
#         stderr when a newer version is available (default, Zero-Config).
# false = disable the check repo-wide (e.g. for offline or corporate setups).
#
# The full opt-out precedence chain:
#   --no-update-check (CLI) > LOAM_NO_UPDATE_CHECK (env) > update_check: false
# ---------------------------------------------------------------------------
# update_check: true

# ---------------------------------------------------------------------------
# auto_update — let loam install new versions by itself (bool, default true)
#
# true  = a pub.dev install or a standalone release binary updates itself in
#         the background (checksum-verified); Homebrew only gets the notice.
# false = keep the update notice, never install. Machine-wide: set
#         LOAM_NO_AUTO_UPDATE. CI and LOAM_OFFLINE never update.
# ---------------------------------------------------------------------------
# auto_update: true

# ---------------------------------------------------------------------------
# required_version — pin the loam version (pub constraint, default: no pin)
#
# A pinned project is never auto-updated. A running version outside the
# constraint prints a warning, and `loam gate` stops with exit code 78.
# ---------------------------------------------------------------------------
# required_version: ">=0.1.15 <0.2.0"

# ---------------------------------------------------------------------------
# strict_baseline — fail `loam gate` on stale baseline entries (bool, default false)
#
# false = stale entries (findings that no longer occur) are only reported.
# true  = they turn the ratchet gate red (for CI); clean up with
#         `loam baseline --prune`. CLI: --strict-baseline / --no-strict-baseline.
# ---------------------------------------------------------------------------
# strict_baseline: false

# ---------------------------------------------------------------------------
# cache — keep the analyzer's summary store between runs (bool, default true)
#
# true  = the analyzer stores what it learned about the SDK, your dependencies
#         and your libraries in .dart_tool/loam/ (trimmed at 512 MB), so the
#         next run resolves faster. Results are identical either way.
# false = resolve from scratch on every run. One run only: --no-cache.
# ---------------------------------------------------------------------------
# cache: true

# ---------------------------------------------------------------------------
# a11y — include accessibility-category rules in `loam scan` (bool, default true)
#
# true  = accessibility rules run as part of `loam scan` (default, Zero-Config).
# false = exclude all accessibility-category rules from `loam scan`.
#         Equivalent to passing --no-a11y on the command line.
#         Use `loam a11y` to run accessibility checks in isolation.
# ---------------------------------------------------------------------------
# a11y: true

# ---------------------------------------------------------------------------
# profile — which rules may block `loam gate` (core | strict, default core)
#
# core   = only rules with a near-zero false-positive rate block the gate.
# strict = every rule blocks, including heuristic and threshold-based ones.
# Rules outside the profile still run and show up as a hint. baseline.json is
# the same for both profiles. Command line: loam gate --profile strict.
# ---------------------------------------------------------------------------
# profile: core

# ---------------------------------------------------------------------------
# rules — per-rule on/off switches (ruleId: true/false)
#
# true  = rule is active (default for every rule).
# false = rule is disabled; its findings are suppressed before any gate check.
#
# Tip: run `loam scan` to see which rules are active in your project.
# ---------------------------------------------------------------------------
rules:
  # Suppress a specific rule project-wide:
  #   unused-public-exports: false

# ---------------------------------------------------------------------------
# source_dirs — top-level directories treated as production source for the
# universal complexity scan (complexity-hotspots, `loam health`).
#
# Default: [lib, bin] — hand-written, shipping Dart code. Generated files
# (*.g.dart, gen-l10n output, …) are ALWAYS excluded regardless of this list.
#
# Deliberately NOT included by default (override here if you want them):
#   test, integration_test, test_driver  — intentionally high complexity
#   example, tool, benchmark             — demo / dev-only code
#
# Note: circular-dependencies and unused-public-exports are inherently a
# lib/ concept and are unaffected by this setting.
# ---------------------------------------------------------------------------
# source_dirs:
#   - lib
#   - bin

# ---------------------------------------------------------------------------
# code_duplicates — intentional boilerplate is not compared by default:
# copyWith, ==, hashCode, toString, toJson/toMap, fromJson/fromMap, props.
# ---------------------------------------------------------------------------
# code_duplicates:
#   boilerplate: true            # false = compare boilerplate too
#   boilerplate_methods: [toXml] # extra method names (matched by name only)

# ---------------------------------------------------------------------------
# unused_public_exports — symbols annotated @visibleForTesting, @internal,
# @protected or @pragma('loam:reserved') are never reported. Add your own
# annotation names here:
# ---------------------------------------------------------------------------
# unused_public_exports:
#   annotations: [Keep]

# ---------------------------------------------------------------------------
# slop_assertion_free_test — a test that never calls expect/verify/check/fail
# (directly or through your own helpers) is reported. List your own assertion
# helpers here, matched by name:
# ---------------------------------------------------------------------------
# slop_assertion_free_test:
#   assertion_functions: [expectGolden]

# ---------------------------------------------------------------------------
# ignore — project-relative glob patterns for path suppression
#
# Findings whose file path matches any glob are suppressed (Source 1).
# Inline `// loam-ignore: <ruleId>` in source code is Source 2.
# Both sources are applied before any gate check.
# ---------------------------------------------------------------------------
ignore:
  # - "lib/generated/**"   # ignore generated files
  # - "**/*.g.dart"        # ignore all .g.dart files
''';
}
