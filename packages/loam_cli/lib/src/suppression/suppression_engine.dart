import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../config/loam_config.dart';
import '../model/finding.dart';
import 'inline_suppression_scanner.dart';

/// Filters [Finding]s based on active suppression sources.
///
/// **Deep Module contract:** callers interact only via [filter] — the internal
/// list of suppression sources is an implementation detail.
///
/// Current suppression sources (applied in order, union):
///   1. **Glob-source:** findings in files matched by [LoamConfig.ignoreGlobs]
///      are removed.
///   2. **Inline-directive source (issue 03):** findings annotated with
///      `// loam-ignore: <ruleId> – <reason>` are removed. Only the exact
///      (filePath, line, ruleId) triple is suppressed; other findings of the
///      same rule at different locations are not affected.
///
/// Glob patterns are matched against **project-relative** paths so that results
/// are machine-independent (Invariant 5 / reproducibility).
///
/// Suppression filters findings only — it does NOT affect [rulesetVersion].
/// The active rule set is unchanged; suppressed findings simply do not appear
/// in the output, the baseline, or the gate evaluation.
abstract final class SuppressionEngine {
  /// Returns a filtered copy of [findings], removing any finding that matches
  /// an active suppression source.
  ///
  /// **Source 1 — Glob:** any finding whose file matches a pattern in
  /// [config.ignoreGlobs] is removed.
  ///
  /// **Source 2 — Inline directives:** any finding whose `(filePath, line,
  /// ruleId)` is covered by a [LoamIgnoreDirective] in [inlineDirectives] is
  /// removed. A directive covers a finding when the directive's [ruleId]
  /// matches and the directive's line equals the finding's line (same line) or
  /// the finding's line equals directive.line + 1 (preceding-line form).
  ///
  /// [projectRoot] must be the absolute, normalised path of the project being
  /// analysed. It is used to derive project-relative paths for glob matching.
  ///
  /// Findings not matched by any suppression source are returned unchanged and
  /// in the same relative order as the input (deterministic, Invariant 5).
  static List<Finding> filter(
    List<Finding> findings,
    LoamConfig config,
    String projectRoot, {
    Set<LoamIgnoreDirective> inlineDirectives = const {},
  }) {
    // Compile globs once per call (they are pure value objects).
    final globs = config.ignoreGlobs.map((pattern) => Glob(pattern)).toList();

    final hasGlobs = globs.isNotEmpty;
    final hasDirectives = inlineDirectives.isNotEmpty;

    // Fast path: no suppression at all → return input unchanged.
    if (!hasGlobs && !hasDirectives) return findings;

    return findings.where((finding) {
      // Source 1: glob suppression.
      if (hasGlobs) {
        final relPath = _relativise(finding.filePath, projectRoot);
        if (_isGlobSuppressed(relPath, globs)) return false;
      }

      // Source 2: inline-directive suppression.
      if (hasDirectives) {
        if (_isInlineSuppressed(finding, inlineDirectives)) return false;
      }

      return true;
    }).toList();
  }

  /// Returns `true` when [relPath] matches any of [globs].
  static bool _isGlobSuppressed(String relPath, List<Glob> globs) {
    for (final glob in globs) {
      if (glob.matches(relPath)) return true;
    }
    return false;
  }

  /// Returns `true` when [finding] is covered by any [LoamIgnoreDirective] in
  /// [directives].
  ///
  /// Matching rule (applied per directive):
  /// - `directive.filePath == finding.filePath`
  /// - `directive.ruleId == finding.ruleId`
  /// - `directive.line == finding.line` (same-line form)
  ///   OR `finding.line == directive.line + 1` (preceding-line form)
  ///
  /// Only the exactly addressed (filePath, line, ruleId) combination is
  /// suppressed. Other findings of the same rule at different lines/files are
  /// NOT affected.
  static bool _isInlineSuppressed(
    Finding finding,
    Set<LoamIgnoreDirective> directives,
  ) {
    for (final directive in directives) {
      if (directive.ruleId != finding.ruleId) continue;
      if (directive.filePath != finding.filePath) continue;
      // Same-line: directive and finding on the same line.
      if (directive.line == finding.line) return true;
      // Preceding-line: directive on the line immediately before the finding.
      if (finding.line == directive.line + 1) return true;
    }
    return false;
  }

  /// Derives a project-relative POSIX path from [absolutePath].
  ///
  /// Uses forward slashes so that patterns like `test/fixtures/**` work
  /// identically on all platforms (Invariant 5).
  static String _relativise(String absolutePath, String projectRoot) {
    // Normalise both paths before computing the relative path.
    final rel = p.relative(absolutePath, from: projectRoot);
    // Convert to forward-slash form for cross-platform glob matching.
    return p.posix.joinAll(p.split(rel));
  }
}
