import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'public_api_collector.dart';
import 'rule.dart';
import 'usage_index.dart';

/// Detects public top-level symbols in `lib/` that are never referenced
/// anywhere in the project.
///
/// Rule ID: `unused-public-exports`
///
/// This is Slice A (Top-Level): only top-level declarations are checked.
/// Member-level analysis is Slice B (future sprint).
///
/// The rule implements the [Rule] interface unchanged — no pipeline modification
/// is needed (Invariant 4). It is deterministic: identical inputs produce
/// identical outputs in identical order (Invariant 5).
///
/// Conservative defaults (in doubt → do NOT report):
/// - Private symbols, entrypoints (`main`), generated files, re-exported
///   symbols, `@visibleForTesting`/`@pragma` annotations are excluded by
///   [PublicApiCollector].
/// - The rule does NOT crash when [ProjectLoadResult.errors] is non-empty;
///   it analyses the resolvable files only.
class UnusedPublicExportsRule implements Rule {
  /// Creates an [UnusedPublicExportsRule] rooted at [projectRoot].
  const UnusedPublicExportsRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  ///
  /// Used to compute POSIX-relative paths for fingerprints and [Finding.filePath].
  final String projectRoot;

  @override
  String get ruleId => 'unused-public-exports';

  @override
  List<Finding> run(ProjectLoadResult result) {
    // Build the project-wide reference index from all resolved files.
    final index = UsageIndex.build(result);

    // Collect public top-level candidates from lib/ files.
    final collector = const PublicApiCollector();
    final candidates = collector.collect(result, projectRoot);

    // Compute the difference: candidates not referenced anywhere.
    final findings = <Finding>[];

    for (final candidate in candidates) {
      if (index.isReferenced(candidate.element)) continue;

      final fingerprint = computeFingerprint(
        ruleId: ruleId,
        relativePath: candidate.relativePath,
        semanticAnchor: candidate.semanticAnchor,
      );

      findings.add(
        Finding(
          ruleId: ruleId,
          severity: Severity.warning,
          filePath: candidate.relativePath,
          line: candidate.line,
          message: 'unused public ${candidate.kind} `${candidate.name}`',
          fingerprint: fingerprint,
        ),
      );
    }

    // Deterministic sort: by relativePath, then by symbol name (semanticAnchor).
    // This satisfies Invariant 5 (reproducibility across runs).
    findings.sort((a, b) {
      final pathCmp = a.filePath.compareTo(b.filePath);
      if (pathCmp != 0) return pathCmp;
      return a.message.compareTo(b.message);
    });

    return findings;
  }
}
