import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'loam_config.dart';

/// Thrown by [ConfigLoader.load] when `loam.yaml` is present but contains
/// a syntax error or an invalid value (e.g. unknown ruleId when validation
/// is enabled).
///
/// Always carries a human-readable [message] — no raw Dart stacktraces
/// are surfaced to the caller (stacktrace-free contract).
class ConfigLoadException implements Exception {
  const ConfigLoadException(this.message);

  final String message;

  @override
  String toString() => 'loam: config error — $message';
}

/// Loads and validates `loam.yaml` from a project root directory.
///
/// Usage:
/// ```dart
/// final config = await ConfigLoader.load(projectRoot,
///     knownRuleIds: AnalysisRunner.fullRegistryIds);
/// ```
///
/// - Missing file → [LoamConfig.defaults] (Zero-Config is the Normalfall).
/// - Present file, valid YAML → parsed [LoamConfig].
/// - Present file, syntax error → [ConfigLoadException] (stacktrace-free).
/// - Unknown ruleId when [knownRuleIds] is non-null → [ConfigLoadException].
///
/// The `ignore` glob list on [LoamConfig] is parsed and stored but glob
/// matching is NOT performed here — that is issue 02.
abstract final class ConfigLoader {
  /// The canonical filename for the loam.dev project configuration.
  static const String fileName = 'loam.yaml';

  /// Loads [LoamConfig] from `<projectRoot>/loam.yaml`.
  ///
  /// [knownRuleIds]: when non-null, any ruleId in the `rules` map that is NOT
  /// in this set triggers a [ConfigLoadException]. When null, no validation is
  /// performed (useful when the full registry is not yet available).
  static Future<LoamConfig> load(
    String projectRoot, {
    Set<String>? knownRuleIds,
  }) async {
    final file = File(p.join(projectRoot, fileName));

    if (!file.existsSync()) {
      return const LoamConfig.defaults();
    }

    final content = file.readAsStringSync();

    // Parse YAML — translate syntax errors into ConfigLoadException.
    YamlMap doc;
    try {
      final raw = loadYaml(content);
      if (raw == null) {
        // Empty file is treated as defaults.
        return const LoamConfig.defaults();
      }
      if (raw is! YamlMap) {
        throw ConfigLoadException(
          '$fileName must be a YAML mapping at the top level, got ${raw.runtimeType}.',
        );
      }
      doc = raw;
    } on YamlException catch (e) {
      throw ConfigLoadException('Failed to parse $fileName: ${e.message}');
    }

    // Parse `rules` section.
    final ruleToggles = <String, bool>{};
    final rawRules = doc['rules'];
    if (rawRules != null) {
      if (rawRules is! YamlMap) {
        throw ConfigLoadException(
          '$fileName: "rules" must be a mapping of ruleId → bool.',
        );
      }
      for (final entry in rawRules.entries) {
        final ruleId = entry.key?.toString();
        if (ruleId == null) continue;

        final value = entry.value;
        if (value is! bool) {
          throw ConfigLoadException(
            '$fileName: rule "$ruleId" must have a boolean value (true/false), '
            'got: $value.',
          );
        }

        // Validate against known registry when provided.
        if (knownRuleIds != null && !knownRuleIds.contains(ruleId)) {
          throw ConfigLoadException(
            '$fileName: unknown ruleId "$ruleId". '
            'Known rules: ${knownRuleIds.join(', ')}.',
          );
        }

        ruleToggles[ruleId] = value;
      }
    }

    // Parse `ignore` section (placeholder — matching in issue 02).
    final ignoreGlobs = <String>[];
    final rawIgnore = doc['ignore'];
    if (rawIgnore != null) {
      if (rawIgnore is! YamlList) {
        throw ConfigLoadException(
          '$fileName: "ignore" must be a list of glob patterns.',
        );
      }
      for (final item in rawIgnore) {
        if (item is! String) {
          throw ConfigLoadException(
            '$fileName: each entry in "ignore" must be a string, got: $item.',
          );
        }
        ignoreGlobs.add(item);
      }
    }

    return LoamConfig(
      ruleToggles: Map.unmodifiable(ruleToggles),
      ignoreGlobs: List.unmodifiable(ignoreGlobs),
    );
  }
}
