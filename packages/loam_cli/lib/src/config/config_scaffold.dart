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
  static String generate() => _content;

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
# Schema: https://github.com/silvio-l/loam (see docs/PRD.md)

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
