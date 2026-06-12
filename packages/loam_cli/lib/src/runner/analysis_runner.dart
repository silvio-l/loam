import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/loam_config.dart';
import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../report/reporter.dart' show ScanStats;
import '../rules/circular_dependencies_rule.dart';
import '../rules/complexity_hotspots_rule.dart';
import '../rules/unused_public_exports_rule.dart';
import '../suppression/inline_suppression_scanner.dart';
import '../suppression/suppression_engine.dart';

/// The full result of one analysis run: the surviving [findings], how many were
/// removed by suppression, and coarse scope [stats].
///
/// [AnalysisRunner.run] / [AnalysisRunner.runWithLoadResult] keep returning a
/// bare `List<Finding>` for callers that only need findings (`gate`,
/// `baseline`, tests). The `analyze*` variants return this richer outcome for
/// the user-facing `scan` report, which surfaces suppression and scope.
class AnalysisOutcome {
  /// Creates an [AnalysisOutcome].
  const AnalysisOutcome({
    required this.findings,
    required this.suppressedCount,
    required this.stats,
    this.stackProfile = const StackProfile.empty(),
  });

  /// The surviving findings, deterministically sorted (post-suppression).
  final List<Finding> findings;

  /// How many raw findings suppression removed (`raw - surviving`).
  final int suppressedCount;

  /// Coarse scope statistics for the run.
  final ScanStats stats;

  /// Read-only stack metadata derived from the project's `pubspec.yaml`.
  ///
  /// Passed through from [ProjectLoadResult.stackProfile]. Never used for
  /// suppression decisions — purely diagnostic (Invariant 1).
  final StackProfile stackProfile;
}

/// The single shared production path from a loaded project to sorted [Finding]s.
///
/// [AnalysisRunner] encapsulates: load project via [ProjectLoader] → iterate
/// the active rule registry → collect all findings → return deterministically
/// sorted results.
///
/// Active registry: [CircularDependenciesRule], [ComplexityHotspotsRule],
/// [UnusedPublicExportsRule].
///
/// Sort key (stable, in order): [Finding.filePath], [Finding.line],
/// [Finding.fingerprint] — guarantees Invariant 5 (reproducibility).
///
/// All consumers — `scan`, `gate`, `baseline` — call exactly this runner.
/// There is no second code path (ADR-0003 / D10).
///
/// [config] controls which rules are active (Rule-Toggles from `loam.yaml`).
/// When omitted, [LoamConfig.defaults] is used (all rules enabled).
class AnalysisRunner {
  /// Creates an [AnalysisRunner]; [config] defaults to all rules enabled.
  const AnalysisRunner({this.config = const LoamConfig.defaults()});

  /// The [LoamConfig] that controls Rule-Toggles and ignore globs.
  ///
  /// Defaults to [LoamConfig.defaults] so that existing call sites that
  /// construct `AnalysisRunner()` without a config remain unchanged.
  final LoamConfig config;

  /// The canonical full registry of all known rule IDs, sorted lexicographically.
  ///
  /// This is the complete set before any config-driven toggles are applied.
  /// [activeRuleIds] is derived from this by removing disabled rules.
  static const List<String> fullRegistryIds = [
    'circular-dependencies',
    'complexity-hotspots',
    'unused-public-exports',
  ];

  /// The config-independent active rule IDs (full registry, no config applied).
  ///
  /// Kept for backwards compatibility with existing callers and tests that
  /// access `AnalysisRunner.activeRuleIds` directly.
  ///
  /// When no [LoamConfig] is in scope, this is the correct set to use.
  static const List<String> activeRuleIds = fullRegistryIds;

  /// Returns the active rule IDs after applying [config]'s Rule-Toggles.
  ///
  /// Rules explicitly disabled (`ruleId → false`) in [config.ruleToggles]
  /// are removed from the full registry. The result is sorted lexicographically
  /// for determinism (Invariant 5).
  static List<String> activeRuleIdsForConfig(LoamConfig config) {
    final ids =
        fullRegistryIds.where((id) => !config.isRuleDisabled(id)).toList()
          ..sort();
    return List.unmodifiable(ids);
  }

  /// A deterministic, content-addressed version string for the active rule set,
  /// ignoring any config (uses the full registry).
  ///
  /// Computed as `ruleset@<8-char SHA-256 hex>` over the sorted [activeRuleIds]
  /// joined by `\n`. Changing the active rule set changes this string, so a
  /// stale baseline will show a rulesetVersion mismatch (Invariant 5 / D8).
  static String get rulesetVersion {
    return _computeVersion(activeRuleIds);
  }

  /// Returns the content-addressed version string for the rule set active
  /// under [config].
  ///
  /// A Rule-Toggle that disables a rule changes [activeRuleIdsForConfig] →
  /// produces a different hash → baseline shows the mismatch (Invariant 5).
  ///
  /// Suppression sources (ignore globs, inline directives) do NOT affect this
  /// version — they filter findings, not the active rule set.
  static String rulesetVersionForConfig(LoamConfig config) {
    return _computeVersion(activeRuleIdsForConfig(config));
  }

  static String _computeVersion(List<String> ids) {
    final content = (List<String>.from(ids)..sort()).join('\n');
    final digest = sha256.convert(utf8.encode(content));
    final short = digest.toString().substring(0, 8);
    return 'ruleset@$short';
  }

  /// Loads the Dart package at [projectRoot] and runs the active rule registry.
  ///
  /// Rules disabled via [config] are not instantiated at all (registry-level
  /// filter — not a post-run finding filter). This ensures the rule produces
  /// no findings, no side effects, and no wasted computation.
  ///
  /// Returns all findings deterministically sorted by
  /// (`filePath`, `line`, `fingerprint`). Never throws in normal operation.
  Future<List<Finding>> run(String projectRoot) async {
    final root = p.normalize(p.absolute(projectRoot));
    final loadResult = await ProjectLoader().load(root);
    return runWithLoadResult(root, loadResult);
  }

  /// Like [run], but returns the richer [AnalysisOutcome] (findings +
  /// suppressed count + scope stats) the `scan` report needs.
  Future<AnalysisOutcome> analyze(String projectRoot) async {
    final root = p.normalize(p.absolute(projectRoot));
    final loadResult = await ProjectLoader().load(root);
    return analyzeWithLoadResult(root, loadResult);
  }

  /// Like [runWithLoadResult], but returns the richer [AnalysisOutcome].
  ///
  /// Used by `ScanCommand` (including the HTML path, which pre-loads the
  /// project to share it with the health sidecar — no second load, no drift).
  AnalysisOutcome analyzeWithLoadResult(
    String projectRoot,
    ProjectLoadResult loadResult,
  ) {
    final root = p.normalize(p.absolute(projectRoot));
    final effectiveIds = activeRuleIdsForConfig(config);
    final rawFindings = _collectRaw(root, loadResult, effectiveIds);

    final inlineDirectives = InlineSuppressionScanner.scan(loadResult, root);
    final findings = SuppressionEngine.filter(
      rawFindings,
      config,
      root,
      inlineDirectives: inlineDirectives,
    );

    findings.sort(_findingOrder);

    return AnalysisOutcome(
      findings: findings,
      suppressedCount: rawFindings.length - findings.length,
      stats: _computeStats(loadResult, effectiveIds),
      stackProfile: loadResult.stackProfile,
    );
  }

  /// Computes coarse scope statistics from the loaded project.
  ScanStats _computeStats(ProjectLoadResult loadResult, List<String> rulesRun) {
    var libFiles = 0;
    var lines = 0;
    for (final file in loadResult.resolved) {
      if (file.isUnderLib) libFiles++;
      lines += file.result.lineInfo.lineCount;
    }
    return ScanStats(
      filesAnalyzed: loadResult.resolved.length,
      libFilesAnalyzed: libFiles,
      linesAnalyzed: lines,
      rulesRun: rulesRun,
    );
  }

  /// Deterministic finding order: filePath → line → fingerprint (Invariant 5).
  static int _findingOrder(Finding a, Finding b) {
    final pathCmp = a.filePath.compareTo(b.filePath);
    if (pathCmp != 0) return pathCmp;
    final lineCmp = a.line.compareTo(b.line);
    if (lineCmp != 0) return lineCmp;
    return a.fingerprint.compareTo(b.fingerprint);
  }

  /// Runs the active rule registry on an already-loaded [ProjectLoadResult].
  ///
  /// This is the shared inner path used by [run] and by callers that have
  /// already loaded the project (e.g. `ScanCommand` when it needs to share the
  /// [ProjectLoadResult] with [FunctionComplexityCollector] for the HTML
  /// health-score sidecar — no second load, no drift).
  ///
  /// [projectRoot] must be the normalised absolute path that was used when
  /// loading [loadResult].
  ///
  /// Returns all findings deterministically sorted by
  /// (`filePath`, `line`, `fingerprint`). Never throws in normal operation.
  List<Finding> runWithLoadResult(
    String projectRoot,
    ProjectLoadResult loadResult,
  ) => analyzeWithLoadResult(projectRoot, loadResult).findings;

  /// Runs the active rule registry and returns the raw, unsuppressed findings.
  ///
  /// [root] must be the normalised absolute project root. The registry is the
  /// full registry minus rules disabled via [config] — disabled rules are not
  /// instantiated at all (registry-level filter, not a post-run finding filter).
  List<Finding> _collectRaw(
    String root,
    ProjectLoadResult loadResult,
    List<String> effectiveIds,
  ) {
    final rules = [
      if (effectiveIds.contains('circular-dependencies'))
        CircularDependenciesRule(projectRoot: root),
      if (effectiveIds.contains('complexity-hotspots'))
        ComplexityHotspotsRule(
          projectRoot: root,
          sourceDirs: config.sourceDirs,
        ),
      if (effectiveIds.contains('unused-public-exports'))
        UnusedPublicExportsRule(projectRoot: root),
    ];

    final rawFindings = <Finding>[];
    for (final rule in rules) {
      rawFindings.addAll(rule.run(loadResult));
    }
    return rawFindings;
  }
}
