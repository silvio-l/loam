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
/// The rule builds a directed library-to-library [ImportGraph] from `import`
/// directives only (a *functional dependency* graph — `export` re-exports are
/// deliberately excluded, see [ImportGraph]), runs [CycleDetector.findCycles]
/// to find all non-trivial strongly connected components (SCCs), and emits
/// exactly one [Finding] per SCC cluster.
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
    // Build the directed library graph (import edges only — exports are
    // re-exports, not functional dependencies; first-party lib/ only, no
    // generated files, no part files).
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

      // Agent-proof classification (see Finding.kind). The remedy explicitly
      // pre-empts the common rationalisation ("this is just the platform /
      // strategy factory pattern, not a real bug") — these ARE real import
      // cycles regardless of the runtime dispatch pattern layered on top.
      final kind = cluster.length == 2
          ? 'bidirectional-cycle'
          : 'multi-file-cycle';
      const remedy =
          'This is a real import cycle, not an artifact of a Platform.isX or '
          'strategy/factory pattern — runtime dispatch does not require these '
          'imports to form a loop. Break it by extracting the shared '
          'abstraction (the abstract interface/base class that the members '
          'import from each other) into its own file, so every import flows in '
          'one direction only. Verify with a fresh scan: the cycle must '
          'disappear, not merely shrink.';

      findings.add(
        Finding(
          ruleId: ruleId,
          severity: Severity.warning,
          filePath: smallestMember,
          line: 1,
          message: 'circular dependency [kind=$kind] between: $membersDisplay',
          fingerprint: fingerprint,
          kind: kind,
          remedy: remedy,
        ),
      );
    }

    // SCCs from CycleDetector are already sorted by smallest member, so the
    // findings list is already in deterministic order (Invariant 5).
    return findings;
  }
}
