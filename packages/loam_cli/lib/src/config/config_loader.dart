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
  /// Creates a [ConfigLoadException] with a human-readable [message].
  const ConfigLoadException(this.message);

  /// Human-readable description of the configuration problem.
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

  /// Loads the effective [LoamConfig] for [projectRoot].
  ///
  /// **Discovery.** loam walks up from [projectRoot] to (and including) the
  /// enclosing git repository root — the directory holding a `.git` entry —
  /// collecting every `loam.yaml` on the way. This matches the mental model of
  /// Dart's own `analysis_options.yaml` (found by walking up) and means a
  /// repo-root config is honoured even when a sub-package is analysed. The walk
  /// is **bounded at the git root** so discovery stays repo-relative and
  /// reproducible across machines and CI (CONTEXT.md Invariant 4) — a
  /// `loam.yaml` above the repository (e.g. in `$HOME`) is never picked up.
  /// When no git root is found, only `<projectRoot>/loam.yaml` is considered.
  ///
  /// **Layering.** Discovered files are merged farthest→nearest so the repo
  /// root provides shared defaults and a nearer (per-package) config builds on
  /// top of it. Merge semantics (nearer wins):
  /// - `rules`: merged per ruleId — the nearer value overrides.
  /// - `ignore`: concatenated farthest-first, de-duplicated, order preserved.
  /// - `source_dirs` / `update_check` / `a11y`: scalar override; a layer that
  ///   omits the key inherits the value from the farther layer.
  ///
  /// [knownRuleIds]: when non-null, any ruleId in the `rules` map of **any**
  /// layer that is NOT in this set triggers a [ConfigLoadException]. When null,
  /// no validation is performed (useful when the full registry is not yet
  /// available).
  static Future<LoamConfig> load(
    String projectRoot, {
    Set<String>? knownRuleIds,
  }) async {
    final files = _discoverConfigFiles(projectRoot); // farthest → nearest
    if (files.isEmpty) {
      return const LoamConfig.defaults();
    }

    var merged = _PartialConfig.empty();
    for (final file in files) {
      merged = merged.overlay(_parseFile(file, knownRuleIds));
    }
    return merged.materialize();
  }

  /// Returns the `loam.yaml` files in scope for [projectRoot], ordered
  /// farthest (git root) → nearest (the project root itself).
  ///
  /// The chain is bounded at the enclosing git repository root; if none is
  /// found up to the filesystem root, only the project root directory is in
  /// scope (no upward walk) — this keeps a machine-global `$HOME/loam.yaml`
  /// from leaking into an ungit-tracked project.
  static List<File> _discoverConfigFiles(String projectRoot) {
    final root = p.normalize(p.absolute(projectRoot));

    // Collect directories nearest → farthest, stopping at the git root.
    final chain = <String>[];
    var dir = root;
    var foundGitRoot = false;
    while (true) {
      chain.add(dir);
      if (_isGitRoot(dir)) {
        foundGitRoot = true;
        break;
      }
      final parent = p.dirname(dir);
      if (parent == dir) break; // filesystem root reached without a .git
      dir = parent;
    }

    final scope = foundGitRoot ? chain : <String>[root];

    // Reverse to farthest → nearest so the merge applies the repo root first.
    final files = <File>[];
    for (final d in scope.reversed) {
      final f = File(p.join(d, fileName));
      if (f.existsSync()) files.add(f);
    }
    return files;
  }

  /// Whether [dir] holds a `.git` entry (directory for a normal clone, file for
  /// a worktree / submodule) — i.e. is a git repository root.
  static bool _isGitRoot(String dir) {
    final git = p.join(dir, '.git');
    return Directory(git).existsSync() || File(git).existsSync();
  }

  /// Parses a single `loam.yaml` [file] into a [_PartialConfig] (absent keys
  /// stay null so layering can tell "omitted" from "set to the default value").
  static _PartialConfig _parseFile(File file, Set<String>? knownRuleIds) {
    final content = file.readAsStringSync();

    YamlMap doc;
    try {
      final raw = loadYaml(content);
      if (raw == null) {
        // Empty file contributes nothing to the merge.
        return _PartialConfig.empty();
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

    return _PartialConfig(
      ruleToggles: _parseRuleToggles(doc, knownRuleIds),
      ignoreGlobs: _parseIgnoreGlobs(doc),
      sourceDirs: _parseSourceDirs(doc),
      updateCheck: _parseUpdateCheck(doc),
      includeA11y: _parseIncludeA11y(doc),
    );
  }

  /// Parses the `rules` mapping (`ruleId → bool`); validates against
  /// [knownRuleIds] when provided. Absent section → empty map.
  static Map<String, bool> _parseRuleToggles(
    YamlMap doc,
    Set<String>? knownRuleIds,
  ) {
    final ruleToggles = <String, bool>{};
    final rawRules = doc['rules'];
    if (rawRules == null) return ruleToggles;
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
      if (knownRuleIds != null && !knownRuleIds.contains(ruleId)) {
        throw ConfigLoadException(
          '$fileName: unknown ruleId "$ruleId". '
          'Known rules: ${knownRuleIds.join(', ')}.',
        );
      }
      ruleToggles[ruleId] = value;
    }
    return ruleToggles;
  }

  /// Parses the `ignore` glob list. Absent section → empty list.
  static List<String> _parseIgnoreGlobs(YamlMap doc) {
    final ignoreGlobs = <String>[];
    final rawIgnore = doc['ignore'];
    if (rawIgnore == null) return ignoreGlobs;
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
    return ignoreGlobs;
  }

  /// Parses `source_dirs` into a deduplicated list of top-level directory
  /// names. Absent section → `null` (the layer inherits / the merge falls back
  /// to [kDefaultSourceDirs] at materialisation).
  static List<String>? _parseSourceDirs(YamlMap doc) {
    final rawSourceDirs = doc['source_dirs'];
    if (rawSourceDirs == null) return null;
    if (rawSourceDirs is! YamlList) {
      throw ConfigLoadException(
        '$fileName: "source_dirs" must be a list of directory names.',
      );
    }
    final parsed = <String>[];
    for (final item in rawSourceDirs) {
      if (item is! String || item.trim().isEmpty) {
        throw ConfigLoadException(
          '$fileName: each entry in "source_dirs" must be a non-empty '
          'string, got: $item.',
        );
      }
      // Normalise to the first path segment (a top-level dir like `lib`).
      final seg = item.trim().replaceAll(r'\', '/').split('/').first;
      if (seg.isNotEmpty && !parsed.contains(seg)) parsed.add(seg);
    }
    return List.unmodifiable(parsed);
  }

  /// Parses the `update_check` boolean. Absent field → `null` (inherit; the
  /// merge falls back to `true` at materialisation).
  static bool? _parseUpdateCheck(YamlMap doc) {
    final rawUpdateCheck = doc['update_check'];
    if (rawUpdateCheck == null) return null;
    if (rawUpdateCheck is! bool) {
      throw ConfigLoadException(
        '$fileName: "update_check" must be a boolean value (true/false), '
        'got: $rawUpdateCheck.',
      );
    }
    return rawUpdateCheck;
  }

  /// Parses the `a11y` boolean toggle for the accessibility-rules category.
  ///
  /// Absent field → `null` (inherit; the merge falls back to `true` at
  /// materialisation — a11y rules are included in scan by default, Zero-Config
  /// is the Normalfall). `a11y: false` excludes all accessibility-category
  /// rules from `loam scan`.
  static bool? _parseIncludeA11y(YamlMap doc) {
    final rawA11y = doc['a11y'];
    if (rawA11y == null) return null;
    if (rawA11y is! bool) {
      throw ConfigLoadException(
        '$fileName: "a11y" must be a boolean value (true/false), '
        'got: $rawA11y.',
      );
    }
    return rawA11y;
  }
}

/// A single `loam.yaml` layer before merging.
///
/// Scalar fields are nullable so the merge can distinguish "key omitted"
/// (inherit the farther layer) from "key set to the default value" (override).
/// Layers are combined farthest→nearest via [overlay]; [materialize] resolves
/// the result into a [LoamConfig], applying the Zero-Config defaults for any
/// field still unset.
class _PartialConfig {
  const _PartialConfig({
    required this.ruleToggles,
    required this.ignoreGlobs,
    required this.sourceDirs,
    required this.updateCheck,
    required this.includeA11y,
  });

  const _PartialConfig.empty()
    : ruleToggles = const {},
      ignoreGlobs = const [],
      sourceDirs = null,
      updateCheck = null,
      includeA11y = null;

  final Map<String, bool> ruleToggles;
  final List<String> ignoreGlobs;
  final List<String>? sourceDirs;
  final bool? updateCheck;
  final bool? includeA11y;

  /// Returns the result of layering [nearer] on top of `this` (the farther
  /// layer). `rules` merge per ruleId, `ignore` lists concatenate (farther
  /// first, de-duplicated), and scalars take the nearer value when present.
  _PartialConfig overlay(_PartialConfig nearer) {
    final mergedToggles = <String, bool>{...ruleToggles, ...nearer.ruleToggles};

    final mergedIgnores = <String>[...ignoreGlobs];
    for (final glob in nearer.ignoreGlobs) {
      if (!mergedIgnores.contains(glob)) mergedIgnores.add(glob);
    }

    return _PartialConfig(
      ruleToggles: mergedToggles,
      ignoreGlobs: mergedIgnores,
      sourceDirs: nearer.sourceDirs ?? sourceDirs,
      updateCheck: nearer.updateCheck ?? updateCheck,
      includeA11y: nearer.includeA11y ?? includeA11y,
    );
  }

  /// Resolves the merged layers into an immutable [LoamConfig], applying the
  /// Zero-Config defaults for any field left unset.
  LoamConfig materialize() => LoamConfig(
    ruleToggles: Map.unmodifiable(ruleToggles),
    ignoreGlobs: List.unmodifiable(ignoreGlobs),
    sourceDirs: sourceDirs ?? kDefaultSourceDirs,
    updateCheck: updateCheck ?? true,
    includeA11y: includeA11y ?? true,
  );
}
