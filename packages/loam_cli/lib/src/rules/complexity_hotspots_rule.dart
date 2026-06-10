import '../complexity/function_complexity_collector.dart';
import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'rule.dart';

/// Default cyclomatic complexity threshold.
///
/// Functions with a cyclomatic complexity **strictly above** this value are
/// reported as hotspots. Conservative default: permits up to 20 independent
/// execution paths, which covers most real-world parsing/dispatch logic;
/// only genuinely complex "god functions" are flagged. Set conservatively to
/// minimise false positives (PRD §12 — "lieber etwas zu hoch ansetzen").
const int kDefaultCyclomaticThreshold = 20;

/// Default cognitive complexity threshold.
///
/// Functions with a cognitive complexity **strictly above** this value are
/// reported as hotspots. The cognitive score grows faster than cyclomatic for
/// deeply nested code; 30 allows substantial but readable nesting while still
/// catching deep-nest / high-cognitive structures. Conservative per PRD §12.
const int kDefaultCognitiveThreshold = 30;

/// Detects functions/methods that exceed the project's complexity budget.
///
/// Rule ID: `complexity-hotspots`
///
/// The rule delegates measurement to [FunctionComplexityCollector], applies
/// documented, fixed default thresholds ([kDefaultCyclomaticThreshold] for
/// cyclomatic, [kDefaultCognitiveThreshold] for cognitive), and emits exactly
/// one [Finding] per breaching executable.
///
/// Finding semantics:
/// - **Severity:** [Severity.warning] — consistent with `unused-public-exports`
///   and `circular-dependencies`.
/// - **Location:** `line` of the executable declaration, no `column`
///   (column is presentation-only for this rule).
/// - **Message:** names the symbol, both metric values, and which threshold
///   was breached.
/// - **Fingerprint:** via `computeFingerprint(ruleId, relativePath,
///   semanticAnchor: qualifiedName)` — stable against line shifts; changes
///   only when the symbol is renamed or moved.
///
/// Trivial executables (cyclomatic == 1 **and** cognitive == 0, i.e. no
/// decision points at all) are never reported even if the thresholds were
/// somehow set to 0 — the guard `cyclomatic > 1 || cognitive > 0` prevents
/// false positives on empty/expression-body functions.
///
/// Generated files (`*.g.dart`, `*.freezed.dart`, etc.) and `bin/` files are
/// excluded by [FunctionComplexityCollector] before findings are produced.
///
/// The rule never crashes when [ProjectLoadResult.errors] is non-empty; it
/// analyses all resolvable files and silently skips unresolvable ones.
///
/// Suppression works automatically via the pipeline-central suppression layer:
/// `loam.yaml` rule toggle and inline `// loam-ignore: complexity-hotspots`
/// both suppress findings without any Rule-level plumbing.
class ComplexityHotspotsRule implements Rule {
  /// The stable rule ID for [ComplexityHotspotsRule].
  ///
  /// Exposed as a static constant so callers can filter findings by rule ID
  /// without instantiating the rule or risking a typo.
  static const String ruleIdStatic = 'complexity-hotspots';

  /// Creates a [ComplexityHotspotsRule] rooted at [projectRoot].
  ///
  /// [projectRoot] is the absolute path of the analysed package.
  /// [cyclomaticThreshold] and [cognitiveThreshold] default to the documented
  /// constants [kDefaultCyclomaticThreshold] and [kDefaultCognitiveThreshold].
  const ComplexityHotspotsRule({
    required this.projectRoot,
    this.cyclomaticThreshold = kDefaultCyclomaticThreshold,
    this.cognitiveThreshold = kDefaultCognitiveThreshold,
    this.collector = const FunctionComplexityCollector(),
  });

  /// Absolute path of the project being analysed.
  final String projectRoot;

  /// Cyclomatic complexity threshold. Functions strictly above this value
  /// are reported.
  final int cyclomaticThreshold;

  /// Cognitive complexity threshold. Functions strictly above this value
  /// are reported.
  final int cognitiveThreshold;

  /// The collector used to enumerate and measure executables.
  final FunctionComplexityCollector collector;

  @override
  String get ruleId => 'complexity-hotspots';

  @override
  List<Finding> run(ProjectLoadResult result) {
    final complexities = collector.collect(result, projectRoot);
    final findings = <Finding>[];

    for (final fc in complexities) {
      final m = fc.metrics;

      // Never report trivial executables (no decision points at all).
      // cyclomatic baseline is 1 (for the function itself), cognitive is 0
      // for a completely straight-line body.
      if (m.cyclomatic <= 1 && m.cognitive == 0) continue;

      final cyclomaticBreached = m.cyclomatic > cyclomaticThreshold;
      final cognitiveBreached = m.cognitive > cognitiveThreshold;

      if (!cyclomaticBreached && !cognitiveBreached) continue;

      // Build a readable description of which threshold(s) were breached.
      final breaches = <String>[];
      if (cyclomaticBreached) {
        breaches.add('cyclomatic ${m.cyclomatic} > $cyclomaticThreshold');
      }
      if (cognitiveBreached) {
        breaches.add('cognitive ${m.cognitive} > $cognitiveThreshold');
      }
      final breachDesc = breaches.join(', ');

      final message =
          '${fc.qualifiedName}: '
          'cyclomatic=${m.cyclomatic}, cognitive=${m.cognitive} '
          '($breachDesc)';

      final fingerprint = computeFingerprint(
        ruleId: ruleId,
        relativePath: fc.filePath,
        semanticAnchor: fc.qualifiedName,
      );

      findings.add(
        Finding(
          ruleId: ruleId,
          severity: Severity.warning,
          filePath: fc.filePath,
          line: fc.line,
          message: message,
          fingerprint: fingerprint,
        ),
      );
    }

    // The collector already sorts by filePath → line → qualifiedName, so the
    // findings list is in deterministic order (Invariant 5).
    return findings;
  }
}
