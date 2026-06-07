import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../config/loam_config.dart';
import '../model/finding.dart';

/// Filters [Finding]s based on active suppression sources.
///
/// **Deep Module contract:** callers interact only via [filter] — the internal
/// list of suppression sources is an implementation detail. Issue 03 adds the
/// inline-directive source additively without touching this contract.
///
/// Current suppression sources (applied in order, union):
///   1. **Glob-source (this issue):** findings in files matched by
///      [LoamConfig.ignoreGlobs] are removed.
///   2. **Inline-directive source (issue 03, not yet implemented):** findings
///      annotated with `// loam-ignore:<ruleId>` are removed.
///
/// Glob patterns are matched against **project-relative** paths so that results
/// are machine-independent (Invariant 5 / reproducibility).
///
/// Suppression filters findings only — it does NOT affect [rulesetVersion].
/// The active rule set is unchanged; suppressed findings simply do not appear
/// in the output, the baseline, or the gate evaluation.
abstract final class SuppressionEngine {
  /// Returns a filtered copy of [findings], removing any finding whose file
  /// matches a glob pattern from [config.ignoreGlobs].
  ///
  /// [projectRoot] must be the absolute, normalised path of the project being
  /// analysed. It is used to derive project-relative paths for glob matching.
  ///
  /// Findings not matched by any suppression source are returned unchanged and
  /// in the same relative order as the input (deterministic, Invariant 5).
  static List<Finding> filter(
    List<Finding> findings,
    LoamConfig config,
    String projectRoot,
  ) {
    // Fast path: no globs configured → return input unchanged.
    if (config.ignoreGlobs.isEmpty) return findings;

    // Compile globs once per call (they are pure value objects).
    final globs = config.ignoreGlobs.map((pattern) => Glob(pattern)).toList();

    return findings.where((finding) {
      final relPath = _relativise(finding.filePath, projectRoot);
      return !_isGlobSuppressed(relPath, globs);
    }).toList();
  }

  /// Returns `true` when [relPath] matches any of [globs].
  static bool _isGlobSuppressed(String relPath, List<Glob> globs) {
    for (final glob in globs) {
      if (glob.matches(relPath)) return true;
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
