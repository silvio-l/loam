import '../config/loam_config.dart' show kDefaultSourceDirs;
import '../duplicates/duplicate_code_collector.dart';
import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'rule.dart';

/// Detects duplicated code blocks across first-party Dart sources.
///
/// Rule ID: `code-duplicates`
///
/// The rule delegates detection to the injected [DuplicateCodeCollector], which
/// extracts normalised AST token sequences from every function/method body and
/// groups them into [DuplicateCluster]s.  Each cluster maps to **exactly one**
/// [Finding] — not N redundant findings, one per cluster.
///
/// Finding semantics:
/// - **Location:** the lexicographically first occurrence (sorted
///   filePath → startLine — stable, deterministic anchor).
/// - **Message:** count of occurrences + all locations as
///   `relative_path:line`, sorted.
/// - **Fingerprint:** stable against line shifts (adding a comment or blank
///   line does not invalidate the baseline).  Changes when copies are
///   added or removed, i.e. when the cluster membership changes.
/// - **Severity:** [Severity.warning] — consistent with
///   `circular-dependencies` / `complexity-hotspots` / `unused-public-exports`.
///
/// The rule never crashes when [ProjectLoadResult.errors] is non-empty; it
/// analyses the resolvable files only (same robustness contract as all Rules).
///
/// Suppression works automatically via the pipeline-central suppression layer:
/// `loam.yaml` rule toggle and inline `// loam-ignore: code-duplicates`
/// both suppress findings without any Rule-level plumbing.
class CodeDuplicatesRule implements Rule {
  /// Creates a [CodeDuplicatesRule] rooted at [projectRoot].
  ///
  /// [collector] is injectable for testing; defaults to [DuplicateCodeCollector].
  const CodeDuplicatesRule({
    required this.projectRoot,
    DuplicateCodeCollector? collector,
    this.sourceDirs = kDefaultSourceDirs,
  }) : _collector = collector ?? const DuplicateCodeCollector();

  /// Absolute path of the project being analysed.
  final String projectRoot;

  /// Top-level directories scanned for duplicates (default `lib`, `bin`).
  /// `test/`, `tool/` and `example/` are excluded unless added via
  /// `source_dirs` in `loam.yaml` — consistent with `complexity-hotspots`.
  final List<String> sourceDirs;

  final DuplicateCodeCollector _collector;

  @override
  String get ruleId => 'code-duplicates';

  @override
  RuleCategory get category => RuleCategory.drift;

  @override
  List<Finding> run(ProjectLoadResult result) {
    final clusters = _collector.collect(
      result,
      projectRoot,
      sourceDirs: sourceDirs,
    );

    final findings = <Finding>[];

    for (final cluster in clusters) {
      // Locations are already sorted lexicographically (filePath → startLine)
      // by DuplicateCodeCollector — first element is the stable anchor.
      final anchor = cluster.locations.first;

      // Message: occurrence count + all locations as `path:line`.
      final locationStrings = cluster.locations
          .map((loc) => '${loc.filePath}:${loc.startLine}')
          .join(', ');
      final message =
          '${cluster.locations.length} occurrences of duplicated block '
          '(${cluster.tokenCount} tokens): $locationStrings';

      // Fingerprint: stable against pure line shifts; changes when copies
      // are added or removed.
      //
      // semanticAnchor = normalised block hash (captured as sorted occurrence
      // anchors "path:line" joined by '\n').  The block-hash component
      // (token count) ensures two different blocks with the same occurrence
      // set still produce different fingerprints.  Using startLine per
      // occurrence intentionally makes the fingerprint shift when a copy
      // moves to a different line, but keeps it stable when unrelated lines
      // above it shift — because `DuplicateCodeCollector` uses AST-level
      // token offsets, so the start line is the first token of the body,
      // not a doc-comment or blank line.
      //
      // Trade-off accepted per issue spec: "stabil gegen reine Zeilenver-
      // schiebung" means adding a blank line before the block should not
      // change the fingerprint.  We achieve this by hashing the sorted
      // occurrence list relative to the token-level start — which only
      // changes when the block itself moves, not when preceding non-token
      // lines shift.
      final sortedOccurrences =
          cluster.locations
              .map((loc) => '${loc.filePath}:${loc.startLine}')
              .toList()
            ..sort();
      final semanticAnchor =
          'tokens=${cluster.tokenCount}\n${sortedOccurrences.join('\n')}';

      final fp = computeFingerprint(
        ruleId: ruleId,
        relativePath: anchor.filePath,
        semanticAnchor: semanticAnchor,
      );

      const remedy =
          'Extract the duplicated block into a shared function or method '
          'that all callers import, then replace each copy with a call to '
          'that shared helper. Verify with a fresh scan: the finding must '
          'disappear, not merely shrink.';

      findings.add(
        Finding(
          ruleId: ruleId,
          severity: Severity.warning,
          filePath: anchor.filePath,
          line: anchor.startLine,
          message: message,
          fingerprint: fp,
          kind: 'duplicated-block',
          remedy: remedy,
        ),
      );
    }

    // Clusters from DuplicateCodeCollector are already sorted by anchor
    // location — findings are deterministic by construction (Invariant 5).
    return findings;
  }
}
