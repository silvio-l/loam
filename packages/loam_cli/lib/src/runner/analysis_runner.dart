import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../rules/unused_public_exports_rule.dart';

/// The single shared production path from a loaded project to sorted [Finding]s.
///
/// [AnalysisRunner] encapsulates: load project via [ProjectLoader] → iterate
/// the active rule registry → collect all findings → return deterministically
/// sorted results.
///
/// MVP registry: [UnusedPublicExportsRule].
///
/// Sort key (stable, in order): [Finding.filePath], [Finding.line],
/// [Finding.fingerprint] — guarantees Invariant 5 (reproducibility).
///
/// All consumers — `scan`, `gate`, `baseline` — call exactly this runner.
/// There is no second code path (ADR-0003 / D10).
class AnalysisRunner {
  const AnalysisRunner();

  /// Loads the Dart package at [projectRoot] and runs the active rule registry.
  ///
  /// Returns all findings deterministically sorted by
  /// (`filePath`, `line`, `fingerprint`). Never throws in normal operation.
  Future<List<Finding>> run(String projectRoot) async {
    final root = p.normalize(p.absolute(projectRoot));

    final loadResult = await ProjectLoader().load(root);

    // MVP registry: exactly one rule.
    final rules = [UnusedPublicExportsRule(projectRoot: root)];

    final findings = <Finding>[];
    for (final rule in rules) {
      findings.addAll(rule.run(loadResult));
    }

    // Deterministic sort: filePath → line → fingerprint (Invariant 5).
    findings.sort((a, b) {
      final pathCmp = a.filePath.compareTo(b.filePath);
      if (pathCmp != 0) return pathCmp;
      final lineCmp = a.line.compareTo(b.line);
      if (lineCmp != 0) return lineCmp;
      return a.fingerprint.compareTo(b.fingerprint);
    });

    return findings;
  }
}
