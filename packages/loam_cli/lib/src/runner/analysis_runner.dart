import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/loam_config.dart';
import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../rules/circular_dependencies_rule.dart';
import '../rules/complexity_hotspots_rule.dart';
import '../rules/unused_public_exports_rule.dart';
import '../suppression/inline_suppression_scanner.dart';
import '../suppression/suppression_engine.dart';

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
  ) {
    final root = p.normalize(p.absolute(projectRoot));

    // Build the registry for this run: full registry minus disabled rules.
    final effectiveIds = activeRuleIdsForConfig(config);

    final rules = [
      if (effectiveIds.contains('circular-dependencies'))
        CircularDependenciesRule(projectRoot: root),
      if (effectiveIds.contains('complexity-hotspots'))
        ComplexityHotspotsRule(projectRoot: root),
      if (effectiveIds.contains('unused-public-exports'))
        UnusedPublicExportsRule(projectRoot: root),
    ];

    final rawFindings = <Finding>[];
    for (final rule in rules) {
      rawFindings.addAll(rule.run(loadResult));
    }

    // Scan for inline `// loam-ignore:` directives using the analyzer's
    // token/comment model (Invariant 1 — no whole-file regex).
    // Passes [root] so that directives carry the same project-relative POSIX
    // paths as Finding.filePath — enabling a plain string equality comparison.
    final inlineDirectives = InlineSuppressionScanner.scan(loadResult, root);

    // Apply suppression BEFORE the deterministic sort (ADR-0003 / D10).
    // scan, gate, and baseline all see the same filtered stream.
    // Source 1 (glob) and Source 2 (inline directives) are combined here.
    final findings = SuppressionEngine.filter(
      rawFindings,
      config,
      root,
      inlineDirectives: inlineDirectives,
    );

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
