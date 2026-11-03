import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/loam_config.dart';
import '../duplicates/boilerplate_matcher.dart';
import '../duplicates/duplicate_code_collector.dart';
import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../progress/progress_sink.dart';
import '../report/reporter.dart' show ScanStats;
import '../rules/a11y_form_field_label_rule.dart';
import '../rules/a11y_icon_button_label_rule.dart';
import '../rules/a11y_image_label_rule.dart';
import '../rules/a11y_interactive_semantics_rule.dart';
import '../rules/architecture_boundaries_rule.dart';
import '../rules/circular_dependencies_rule.dart';
import '../rules/code_duplicates_rule.dart';
import '../rules/complexity_hotspots_rule.dart';
import '../rules/hardcoded_secrets_rule.dart';
import '../rules/rule.dart';
import '../rules/slop_assertion_free_test_rule.dart';
import '../rules/slop_empty_catch_rule.dart';
import '../rules/slop_narrative_comment_rule.dart';
import '../rules/slop_placeholder_comment_rule.dart';
import '../rules/slop_setstate_after_async_gap_rule.dart';
import '../rules/slop_tautological_assertion_rule.dart';
import '../rules/slop_undisposed_resource_rule.dart';
import '../rules/slop_unimplemented_stub_rule.dart';
import '../rules/slop_unjustified_ignore_rule.dart';
import '../rules/slop_workflow_narration_comment_rule.dart';
import '../rules/unused_public_exports_rule.dart';
import '../suppression/inline_suppression_scanner.dart';
import '../suppression/suppression_audit.dart';
import '../suppression/suppression_engine.dart';
import '../timing/phase_timer.dart';

DateTime _systemClock() => DateTime.now();

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
    this.suppressionAudit = const SuppressionAudit.empty(),
  });

  /// The surviving findings, deterministically sorted (post-suppression).
  final List<Finding> findings;

  /// How many raw findings suppression removed (`raw - surviving`).
  final int suppressedCount;

  /// Coarse scope statistics for the run.
  final ScanStats stats;

  /// Suppressions per rule plus warnings about unused, expired or malformed
  /// `// loam-ignore:` directives. Warnings only — never part of [findings].
  final SuppressionAudit suppressionAudit;

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
/// Active registry: [A11yFormFieldLabelRule], [A11yIconButtonLabelRule],
/// [A11yImageLabelRule], [A11yInteractiveSemanticsRule],
/// [CircularDependenciesRule], [CodeDuplicatesRule],
/// [ComplexityHotspotsRule], [HardcodedSecretsRule], [SlopEmptyCatchRule],
/// [SlopAssertionFreeTestRule], [SlopTautologicalAssertionRule],
/// [SlopNarrativeCommentRule], [SlopPlaceholderCommentRule],
/// [SlopSetStateAfterAsyncGapRule],
/// [SlopUndisposedResourceRule], [SlopUnimplementedStubRule],
/// [SlopUnjustifiedIgnoreRule],
/// [SlopWorkflowNarrationCommentRule], [UnusedPublicExportsRule].
///
/// Sort key (stable, in order): [Finding.filePath], [Finding.line],
/// [Finding.fingerprint] — guarantees Invariant 5 (reproducibility).
///
/// All consumers — `scan`, `gate`, `baseline` — call exactly this runner.
/// There is no second code path (ADR-0003 / D10).
///
/// [config] controls which rules are active (Rule-Toggles from `loam.yaml`
/// and the `a11y`/`includeA11y` category toggle). When omitted,
/// [LoamConfig.defaults] is used (all rules enabled).
///
/// [categoryFilter] restricts the run to a single [RuleCategory] (e.g.
/// [RuleCategory.accessibility] for `loam a11y`). Category membership is
/// looked up in [_ruleCategories] — never via ruleId string prefixes
/// (Invariant 1: semantics over syntax).
class AnalysisRunner {
  /// Creates an [AnalysisRunner]; [config] defaults to all rules enabled.
  ///
  /// [categoryFilter]: when set, only rules belonging to this category are run.
  /// Defaults to `null` (all categories active, subject to [config]).
  ///
  /// [progressSink]: receives semantic progress events during both the load
  /// phase (delegated to [ProjectLoader]) and the analysis phase (one advance
  /// per rule). Defaults to [NoopProgressSink] so existing callers that omit
  /// this argument get zero overhead (no `if (sink != null)` guards needed).
  const AnalysisRunner({
    this.config = const LoamConfig.defaults(),
    this.categoryFilter,
    this.progressSink = const NoopProgressSink(),
    this.clock = _systemClock,
    this.analyzerCacheDirectory,
  });

  /// Where the analyzer keeps its summary store between runs, or `null`
  /// (default) for an in-memory store. Passed to [ProjectLoader.load] by [run]
  /// and [analyze]; the CLI sets it unless caching is off (`--no-cache`,
  /// `cache: false`). Findings are identical either way.
  final String? analyzerCacheDirectory;

  /// Source of "today" for `until=` expiry of `// loam-ignore:` directives.
  /// Injectable so expiry is testable without waiting.
  final DateTime Function() clock;

  /// The [LoamConfig] that controls Rule-Toggles and ignore globs.
  ///
  /// Defaults to [LoamConfig.defaults] so that existing call sites that
  /// construct `AnalysisRunner()` without a config remain unchanged.
  final LoamConfig config;

  /// When set, only rules belonging to this [RuleCategory] are run.
  ///
  /// `null` (default) means all categories are active, subject to [config].
  /// Category membership is determined by [_ruleCategories] — not by ruleId
  /// string prefixes (Invariant 1: semantics over syntax).
  final RuleCategory? categoryFilter;

  /// Receives semantic progress events (load phase + analysis phase).
  ///
  /// Defaults to [NoopProgressSink] — no I/O overhead for callers that omit
  /// this argument (gate, baseline, health commands).
  final ProgressSink progressSink;

  /// The canonical full registry of all known rule IDs, sorted lexicographically.
  ///
  /// This is the complete set before any config-driven toggles are applied.
  /// [activeRuleIds] is derived from this by removing disabled rules.
  static const List<String> fullRegistryIds = [
    'a11y-form-field-label',
    'a11y-icon-button-label',
    'a11y-image-label',
    'a11y-interactive-semantics',
    'architecture-boundaries',
    'circular-dependencies',
    'code-duplicates',
    'complexity-hotspots',
    'hardcoded-secrets',
    'slop-assertion-free-test',
    'slop-empty-catch',
    'slop-narrative-comment',
    'slop-placeholder-comment',
    'slop-setstate-after-async-gap',
    'slop-tautological-assertion',
    'slop-undisposed-resource',
    'slop-unimplemented-stub',
    'slop-unjustified-ignore',
    'slop-workflow-narration-comment',
    'unused-public-exports',
  ];

  /// Maps every rule ID in [fullRegistryIds] to its [RuleCategory].
  ///
  /// This is the authoritative category mapping — category membership is
  /// determined here, never by ruleId string prefixes (Invariant 1). When a
  /// new rule is registered, add its ID to both [fullRegistryIds] and here.
  static const Map<String, RuleCategory> _ruleCategories = {
    'a11y-form-field-label': RuleCategory.accessibility,
    'a11y-icon-button-label': RuleCategory.accessibility,
    'a11y-image-label': RuleCategory.accessibility,
    'a11y-interactive-semantics': RuleCategory.accessibility,
    'architecture-boundaries': RuleCategory.drift,
    'circular-dependencies': RuleCategory.drift,
    'code-duplicates': RuleCategory.drift,
    'complexity-hotspots': RuleCategory.drift,
    'hardcoded-secrets': RuleCategory.slop,
    'slop-assertion-free-test': RuleCategory.slop,
    'slop-empty-catch': RuleCategory.slop,
    'slop-narrative-comment': RuleCategory.slop,
    'slop-placeholder-comment': RuleCategory.slop,
    'slop-setstate-after-async-gap': RuleCategory.slop,
    'slop-tautological-assertion': RuleCategory.slop,
    'slop-undisposed-resource': RuleCategory.slop,
    'slop-unimplemented-stub': RuleCategory.slop,
    'slop-unjustified-ignore': RuleCategory.slop,
    'slop-workflow-narration-comment': RuleCategory.slop,
    'unused-public-exports': RuleCategory.drift,
  };

  /// The config-independent active rule IDs (full registry, no config applied).
  ///
  /// Kept for backwards compatibility with existing callers and tests that
  /// access `AnalysisRunner.activeRuleIds` directly.
  ///
  /// When no [LoamConfig] is in scope, this is the correct set to use.
  static const List<String> activeRuleIds = fullRegistryIds;

  /// Returns the active rule IDs belonging to [cat] in the full registry,
  /// sorted lexicographically.
  ///
  /// Derived from [fullRegistryIds] × [_ruleCategories] — does NOT use ruleId
  /// string prefixes (Invariant 1: semantics over syntax).
  static List<String> activeIdsForCategory(RuleCategory cat) {
    return (fullRegistryIds.where((id) => _ruleCategories[id] == cat).toList()
      ..sort());
  }

  /// Returns the active rule IDs after applying [config]'s Rule-Toggles and
  /// the [LoamConfig.includeA11y] category toggle.
  ///
  /// Rules explicitly disabled (`ruleId → false`) in [config.ruleToggles]
  /// are removed. When [config.includeA11y] is `false`, all rules belonging
  /// to [RuleCategory.accessibility] are also removed.
  ///
  /// The result is sorted lexicographically for determinism (Invariant 5).
  static List<String> activeRuleIdsForConfig(LoamConfig config) {
    final ids = fullRegistryIds.where((id) {
      if (config.isRuleDisabled(id)) return false;
      if (!config.includeA11y &&
          _ruleCategories[id] == RuleCategory.accessibility) {
        return false;
      }
      return true;
    }).toList()..sort();
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

  /// Returns the content-addressed version string for the subset of rules
  /// belonging to [cat] and active under [config].
  ///
  /// Category membership is determined by [_ruleCategories] (not ruleId
  /// prefixes). Config-disabled rules are excluded. When there are no
  /// rules for [cat], returns the hash of the empty set.
  static String rulesetVersionForCategory(RuleCategory cat, LoamConfig config) {
    final ids = activeIdsForCategory(
      cat,
    ).where((id) => !config.isRuleDisabled(id)).toList()..sort();
    return _computeVersion(ids);
  }

  /// Per-rule revisions above 1: bumped when a rule's results change for the
  /// same source, so existing baselines show a ruleset mismatch.
  ///
  /// - `complexity-hotspots` 2: counts switch expressions, collection
  ///   `if`/`for`, if-case conditions and logical patterns.
  static const Map<String, int> _ruleRevisions = {'complexity-hotspots': 2};

  static String _computeVersion(List<String> ids) {
    final content = (List<String>.from(ids)..sort())
        .map((id) {
          final revision = _ruleRevisions[id];
          return revision == null ? id : '$id@$revision';
        })
        .join('\n');
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
  Future<List<Finding>> run(String projectRoot) async =>
      (await analyze(projectRoot)).findings;

  /// Like [run], but returns the richer [AnalysisOutcome] (findings +
  /// suppressed count + scope stats) the `scan` report needs.
  ///
  /// When every active rule is a [FileRule] (e.g. `loam slop`), the project is
  /// only parsed, not resolved: those rules and the suppression scan read
  /// nothing but each file's own AST. Files with semantic errors (say, an
  /// unresolved import) are then checked too; only syntax errors exclude a
  /// file.
  Future<AnalysisOutcome> analyze(String projectRoot) async {
    final root = p.normalize(p.absolute(projectRoot));
    final rules = _instantiate(root, _effectiveIds());
    final loadResult = await ProjectLoader().load(
      root,
      progressSink: progressSink,
      cacheDirectory: analyzerCacheDirectory,
      parseOnly: rules.every((rule) => rule is FileRule),
    );
    return _analyzeLoaded(root, loadResult, rules);
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
    return _analyzeLoaded(
      root,
      loadResult,
      _instantiate(root, _effectiveIds()),
    );
  }

  /// Config-filtered rule IDs with the optional category filter applied.
  /// Both filters are applied here (registry-level, before instantiation) —
  /// not as a post-run filter on findings (Invariant 1 / issue AC spec).
  List<String> _effectiveIds() {
    final configIds = activeRuleIdsForConfig(config);
    return categoryFilter == null
        ? configIds
        : (configIds
              .where((id) => _ruleCategories[id] == categoryFilter)
              .toList()
            ..sort());
  }

  AnalysisOutcome _analyzeLoaded(
    String root,
    ProjectLoadResult loadResult,
    List<Rule> rules,
  ) {
    final effectiveIds = [for (final rule in rules) rule.ruleId];

    // Fire analysis-phase progress: one advance per active rule.
    progressSink.startPhase('Analysiere', total: effectiveIds.length);
    final timer = PhaseTimer.active;
    final List<Finding> rawFindings;
    final stopRules = timer?.begin('rules');
    try {
      rawFindings = _collectRaw(loadResult, rules);
    } finally {
      stopRules?.call();
      progressSink.endPhase();
    }

    final stopSuppression = timer?.begin('suppression');
    final scanned = InlineSuppressionScanner.scanWithIssues(loadResult, root);
    final suppression = SuppressionEngine.apply(
      rawFindings,
      config,
      root,
      inlineDirectives: scanned.directives,
      scanIssues: scanned.issues,
      auditedRuleIds: effectiveIds.toSet(),
      knownRuleIds: fullRegistryIds.toSet(),
      today: clock(),
    );
    final findings = [...suppression.findings];
    stopSuppression?.call();

    findings.sort(_findingOrder);

    return AnalysisOutcome(
      findings: findings,
      suppressedCount: rawFindings.length - findings.length,
      stats: _computeStats(loadResult, effectiveIds),
      stackProfile: loadResult.stackProfile,
      suppressionAudit: suppression.audit,
    );
  }

  /// Computes coarse scope statistics from the loaded project.
  ScanStats _computeStats(ProjectLoadResult loadResult, List<String> rulesRun) {
    var libFiles = 0;
    var lines = 0;
    for (final file in loadResult.resolved) {
      if (file.isUnderLib) libFiles++;
      lines += file.parsed.lineInfo.lineCount;
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

  /// Runs [rules] over [loadResult] and returns the raw, unsuppressed findings.
  ///
  /// Fires one [ProgressSink.advance] per rule so the caller can track progress
  /// against the rule count passed to `startPhase`.
  List<Finding> _collectRaw(ProjectLoadResult loadResult, List<Rule> rules) {
    final rawFindings = <Finding>[];
    final timer = PhaseTimer.active;
    for (final rule in rules) {
      final stopRule = timer?.begin(rule.ruleId, depth: 1);
      rawFindings.addAll(rule.run(loadResult));
      stopRule?.call();
      progressSink.advance();
    }
    return rawFindings;
  }

  /// Instantiates the rules in [effectiveIds] (registry order) for the
  /// normalised absolute project [root]. The registry is the full registry
  /// minus rules disabled via [config] — disabled rules are not instantiated
  /// at all (registry-level filter, not a post-run finding filter).
  List<Rule> _instantiate(String root, List<String> effectiveIds) {
    final factories = <String, Rule Function()>{
      'a11y-form-field-label': () => A11yFormFieldLabelRule(projectRoot: root),
      'a11y-icon-button-label': () =>
          A11yIconButtonLabelRule(projectRoot: root),
      'a11y-image-label': () => A11yImageLabelRule(projectRoot: root),
      'a11y-interactive-semantics': () =>
          A11yInteractiveSemanticsRule(projectRoot: root),
      'architecture-boundaries': () => ArchitectureBoundariesRule(
        projectRoot: root,
        layers: config.layers,
        boundaries: config.boundaries,
      ),
      'circular-dependencies': () =>
          CircularDependenciesRule(projectRoot: root),
      'code-duplicates': () => CodeDuplicatesRule(
        projectRoot: root,
        collector: const DuplicateCodeCollector(),
        sourceDirs: config.sourceDirs,
        boilerplate: config.skipBoilerplate
            ? BoilerplateMatcher(extraNames: config.boilerplateMethods.toSet())
            : const BoilerplateMatcher.disabled(),
      ),
      'complexity-hotspots': () => ComplexityHotspotsRule(
        projectRoot: root,
        sourceDirs: config.sourceDirs,
      ),
      'hardcoded-secrets': () => HardcodedSecretsRule(projectRoot: root),
      'slop-assertion-free-test': () => SlopAssertionFreeTestRule(
        projectRoot: root,
        assertionFunctions: config.assertionFunctions,
      ),
      'slop-empty-catch': () => SlopEmptyCatchRule(projectRoot: root),
      'slop-narrative-comment': () =>
          SlopNarrativeCommentRule(projectRoot: root),
      'slop-placeholder-comment': () =>
          SlopPlaceholderCommentRule(projectRoot: root),
      'slop-setstate-after-async-gap': () =>
          SlopSetStateAfterAsyncGapRule(projectRoot: root),
      'slop-tautological-assertion': () =>
          SlopTautologicalAssertionRule(projectRoot: root),
      'slop-undisposed-resource': () =>
          SlopUndisposedResourceRule(projectRoot: root),
      'slop-unimplemented-stub': () => SlopUnimplementedStubRule(
        projectRoot: root,
        sourceDirs: config.sourceDirs,
      ),
      'slop-unjustified-ignore': () =>
          SlopUnjustifiedIgnoreRule(projectRoot: root),
      'slop-workflow-narration-comment': () =>
          SlopWorkflowNarrationCommentRule(projectRoot: root),
      'unused-public-exports': () => UnusedPublicExportsRule(
        projectRoot: root,
        extraAnnotations: config.reservedAnnotations.toSet(),
      ),
    };
    return [for (final id in effectiveIds) ?factories[id]?.call()];
  }
}
