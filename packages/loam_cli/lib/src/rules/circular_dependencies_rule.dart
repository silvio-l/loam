import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'cycle_detector.dart';
import 'import_graph.dart';
import 'rule.dart';

/// Detects circular dependencies between first-party `lib/` libraries.
///
/// Rule ID: `circular-dependencies`
///
/// The rule builds a directed library-to-library [ImportGraph] (both `import`
/// and `export` directives), runs [CycleDetector.findCycles] to find all
/// non-trivial strongly connected components (SCCs), and emits exactly one
/// [Finding] per SCC cluster.
///
/// Finding semantics:
/// - **Location:** the lexicographically smallest member of the cluster,
///   `line = 1`, no column (file-level finding).
/// - **Message:** names all cluster members (sorted), so a human can see the
///   full loop at a glance.
/// - **Fingerprint:** stable against line/import-order shifts; changes only
///   when the cluster membership changes (Invariant 5).
/// - **Severity:** [Severity.warning] — consistent with `unused-public-exports`.
///
/// The rule never crashes when [ProjectLoadResult.errors] is non-empty; it
/// analyses the resolvable files only (same robustness contract as all Rules).
///
/// Suppression works automatically via the pipeline-central suppression layer:
/// `loam.yaml` rule toggle and inline `// loam-ignore: circular-dependencies`
/// both suppress findings without any Rule-level plumbing.
class CircularDependenciesRule implements Rule {
  /// Creates a [CircularDependenciesRule] rooted at [projectRoot].
  const CircularDependenciesRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  ///
  /// Used to resolve relative POSIX paths for [ImportGraph.build].
  final String projectRoot;

  @override
  String get ruleId => 'circular-dependencies';

  @override
  List<Finding> run(ProjectLoadResult result) {
    // Build the directed library graph (import + export edges, first-party
    // lib/ only, no generated files, no part files).
    final graph = ImportGraph.build(result, projectRoot);

    // Find all non-trivial SCCs (cycles) using Tarjan's algorithm.
    // CycleDetector already returns members sorted and SCCs sorted by their
    // smallest member — deterministic by construction (Invariant 5).
    final cycles = CycleDetector().findCycles(graph.edges);

    final findings = <Finding>[];

    for (final cluster in cycles) {
      // cluster is already sorted (CycleDetector guarantees this).
      // Smallest member = cluster.first (lexicographic minimum).
      final smallestMember = cluster.first;

      // semanticAnchor: all member paths joined by '\n', sorted.
      // Stable against line/import-order shifts; changes iff the cluster
      // membership changes (a file joins or leaves) — new Finding, new
      // fingerprint — correct and intentional (issue spec).
      final semanticAnchor = cluster.join('\n');

      final fingerprint = computeFingerprint(
        ruleId: ruleId,
        relativePath: smallestMember,
        semanticAnchor: semanticAnchor,
      );

      // Message: list the member files so the developer can see the loop.
      final membersDisplay = cluster.join(', ');

      findings.add(
        Finding(
          ruleId: ruleId,
          severity: Severity.warning,
          filePath: smallestMember,
          line: 1,
          message: 'circular dependency between: $membersDisplay',
          fingerprint: fingerprint,
        ),
      );
    }

    // SCCs from CycleDetector are already sorted by smallest member, so the
    // findings list is already in deterministic order (Invariant 5).
    return findings;
  }
}
