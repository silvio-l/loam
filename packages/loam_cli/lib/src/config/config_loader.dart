import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../rules/rule_profile.dart';
import 'architecture_config.dart';
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
  /// reproducible across machines and CI (internal-notes Invariant 5) — a
  /// `loam.yaml` above the repository (e.g. in `$HOME`) is never picked up.
  /// When no git root is found, only `<projectRoot>/loam.yaml` is considered.
  ///
  /// **Layering.** Discovered files are merged farthest→nearest so the repo
  /// root provides shared defaults and a nearer (per-package) config builds on
  /// top of it. Merge semantics (nearer wins):
  /// - `rules`: merged per ruleId — the nearer value overrides.
  /// - `ignore`: concatenated farthest-first, de-duplicated, order preserved.
  /// - `code_duplicates.boilerplate_methods` and
  ///   `unused_public_exports.annotations` and
  ///   `slop_assertion_free_test.assertion_functions`: lists are united across
  ///   layers;
  ///   `code_duplicates.boilerplate` is a scalar override.
  /// - `source_dirs` / `update_check` / `a11y` / `auto_update` /
  ///   `required_version` / `profile` / `strict_baseline` / `cache`: scalar
  ///   override; a layer that omits the key inherits the value from the farther
  ///   layer.
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
    final config = merged.materialize();
    _validateBoundaries(config);
    return config;
  }

  /// Every layer named in a boundary must be a configured layer - a typo would
  /// otherwise silently disable the boundary.
  static void _validateBoundaries(LoamConfig config) {
    for (final b in config.boundaries) {
      for (final name in [b.from, ...b.deny]) {
        if (!config.layers.containsKey(name)) {
          throw ConfigLoadException(
            '$fileName: boundary refers to unknown layer "$name". '
            'Known layers: ${config.layers.keys.join(', ')}.',
          );
        }
      }
    }
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

    final codeDuplicates = _parseSection(doc, 'code_duplicates', const {
      'boilerplate',
      'boilerplate_methods',
    });
    final unusedExports = _parseSection(doc, 'unused_public_exports', const {
      'annotations',
    });

    final assertionFree = _parseSection(doc, 'slop_assertion_free_test', const {
      'assertion_functions',
    });

    return _PartialConfig(
      ruleToggles: _parseRuleToggles(doc, knownRuleIds),
      ignoreGlobs: _parseIgnoreGlobs(doc),
      sourceDirs: _parseSourceDirs(doc),
      updateCheck: _parseUpdateCheck(doc),
      includeA11y: _parseIncludeA11y(doc),
      autoUpdate: _parseBool(doc, 'auto_update'),
      requiredVersion: _parseRequiredVersion(doc),
      profile: _parseProfile(doc),
      strictBaseline: _parseBool(doc, 'strict_baseline'),
      cache: _parseBool(doc, 'cache'),
      skipBoilerplate: _parseBool(codeDuplicates, 'boilerplate'),
      boilerplateMethods:
          _parseNameList(codeDuplicates, 'boilerplate_methods') ?? const [],
      reservedAnnotations:
          _parseNameList(unusedExports, 'annotations') ?? const [],
      assertionFunctions:
          _parseNameList(assertionFree, 'assertion_functions') ?? const [],
      layers: _parseLayers(doc),
      boundaries: _parseBoundaries(doc),
    );
  }

  /// Reads the optional mapping [section] (whose only legal keys are
  /// [allowedKeys]). Absent section → an empty map. An unknown key is a
  /// [ConfigLoadException], so a typo can never silently disable a setting.
  static YamlMap _parseSection(
    YamlMap doc,
    String section,
    Set<String> allowedKeys,
  ) {
    final raw = doc[section];
    if (raw == null) return YamlMap();
    if (raw is! YamlMap) {
      throw ConfigLoadException('$fileName: "$section" must be a mapping.');
    }
    for (final key in raw.keys) {
      if (!allowedKeys.contains(key.toString())) {
        throw ConfigLoadException(
          '$fileName: unknown key "$key" in "$section". '
          'Known keys: ${allowedKeys.join(', ')}.',
        );
      }
    }
    return raw;
  }

  /// Parses an optional list of non-empty identifier names under [key].
  /// Absent → `null`.
  static List<String>? _parseNameList(YamlMap section, String key) {
    final raw = section[key];
    if (raw == null) return null;
    if (raw is! YamlList) {
      throw ConfigLoadException('$fileName: "$key" must be a list of names.');
    }
    final names = <String>[];
    for (final item in raw) {
      final name = item is String ? item.trim().replaceFirst('@', '') : '';
      if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name)) {
        throw ConfigLoadException(
          '$fileName: each entry in "$key" must be a plain identifier, '
          'got: $item.',
        );
      }
      if (!names.contains(name)) names.add(name);
    }
    return names;
  }

  /// Parses `layers` (`name: project-relative/dir`). Absent -> empty.
  static Map<String, String> _parseLayers(YamlMap doc) {
    final raw = doc['layers'];
    if (raw == null) return const {};
    if (raw is! YamlMap) {
      throw ConfigLoadException(
        '$fileName: "layers" must be a mapping of layer name -> directory.',
      );
    }
    final layers = <String, String>{};
    for (final entry in raw.entries) {
      final dir = entry.value;
      if (dir is! String || dir.trim().isEmpty) {
        throw ConfigLoadException(
          '$fileName: layer "${entry.key}" must map to a non-empty '
          'directory string, got: $dir.',
        );
      }
      layers['${entry.key}'] = normalizeLayerDir('${entry.key}', dir);
    }
    return layers;
  }

  /// Brings a layer directory from `loam.yaml` into the form the boundary rule
  /// compares against: project-relative POSIX, no `./`, no trailing `/`
  /// (`./lib/core/`, `lib\core` -> `lib/core`).
  ///
  /// Throws [ConfigLoadException] for an absolute path, a path that leaves the
  /// project, or one that names the project root itself.
  static String normalizeLayerDir(String layer, String dir) {
    final posix = dir.trim().replaceAll(r'\', '/');
    if (posix.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(posix)) {
      throw ConfigLoadException(
        '$fileName: layer "$layer" must be a directory relative to the '
        'project root, not an absolute path, got: "$dir". Write it as e.g. '
        '"lib/core".',
      );
    }
    final normalized = p.posix.normalize(posix);
    if (normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw ConfigLoadException(
        '$fileName: layer "$layer" must name a directory inside the project, '
        'got: "$dir". Write it relative to the project root, e.g. "lib/core".',
      );
    }
    return normalized;
  }

  /// Parses `boundaries` (list of `{from: layer, deny: [layers]}`).
  static List<LayerBoundary> _parseBoundaries(YamlMap doc) {
    final raw = doc['boundaries'];
    if (raw == null) return const [];
    if (raw is! YamlList) {
      throw ConfigLoadException(
        '$fileName: "boundaries" must be a list of {from, deny} entries.',
      );
    }
    final boundaries = <LayerBoundary>[];
    for (final item in raw) {
      final from = item is YamlMap ? item['from'] : null;
      final deny = item is YamlMap ? item['deny'] : null;
      if (from is! String ||
          deny is! YamlList ||
          deny.isEmpty ||
          deny.any((d) => d is! String)) {
        throw ConfigLoadException(
          '$fileName: each entry in "boundaries" needs "from" (a layer name) '
          'and a non-empty "deny" list of layer names, got: $item.',
        );
      }
      boundaries.add(
        LayerBoundary(from: from, deny: List.unmodifiable(deny.cast<String>())),
      );
    }
    return boundaries;
  }

  /// Parses an optional boolean [key]. Absent → `null` (inherit).
  static bool? _parseBool(YamlMap doc, String key) {
    final raw = doc[key];
    if (raw == null) return null;
    if (raw is! bool) {
      throw ConfigLoadException(
        '$fileName: "$key" must be a boolean value (true/false), got: $raw.',
      );
    }
    return raw;
  }

  /// Parses `profile` (`core` | `strict`). Absent → `null` (inherit).
  static RuleProfile? _parseProfile(YamlMap doc) {
    final raw = doc['profile'];
    if (raw == null) return null;
    final parsed = raw is String ? RuleProfile.tryParse(raw) : null;
    if (parsed == null) {
      throw ConfigLoadException(
        '$fileName: "profile" must be one of '
        '${RuleProfile.values.map((v) => v.name).join(', ')}, got: $raw.',
      );
    }
    return parsed;
  }

  /// Parses `required_version` as a pub version constraint (`">=0.1.15
  /// <0.2.0"`, `"^0.1.15"` or an exact `"0.1.15"`). Absent → `null`.
  static VersionConstraint? _parseRequiredVersion(YamlMap doc) {
    final raw = doc['required_version'];
    if (raw == null) return null;
    try {
      return VersionConstraint.parse(raw.toString());
    } on FormatException {
      throw ConfigLoadException(
        '$fileName: "required_version" must be a version constraint such as '
        '">=0.1.15 <0.2.0" or "0.1.15", got: $raw.',
      );
    }
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
    this.autoUpdate,
    this.requiredVersion,
    this.profile,
    this.strictBaseline,
    this.cache,
    this.skipBoilerplate,
    this.boilerplateMethods = const [],
    this.reservedAnnotations = const [],
    this.assertionFunctions = const [],
    this.layers = const {},
    this.boundaries = const [],
  });

  const _PartialConfig.empty()
    : ruleToggles = const {},
      ignoreGlobs = const [],
      sourceDirs = null,
      updateCheck = null,
      includeA11y = null,
      autoUpdate = null,
      requiredVersion = null,
      profile = null,
      strictBaseline = null,
      cache = null,
      skipBoilerplate = null,
      boilerplateMethods = const [],
      reservedAnnotations = const [],
      assertionFunctions = const [],
      layers = const {},
      boundaries = const [];

  final Map<String, bool> ruleToggles;
  final List<String> ignoreGlobs;
  final List<String>? sourceDirs;
  final bool? updateCheck;
  final bool? includeA11y;
  final bool? autoUpdate;
  final VersionConstraint? requiredVersion;
  final RuleProfile? profile;
  final bool? strictBaseline;
  final bool? cache;
  final bool? skipBoilerplate;
  final List<String> boilerplateMethods;
  final List<String> reservedAnnotations;
  final List<String> assertionFunctions;
  final Map<String, String> layers;
  final List<LayerBoundary> boundaries;

  /// Returns the result of layering [nearer] on top of `this` (the farther
  /// layer). `rules` merge per ruleId, `ignore` lists concatenate (farther
  /// first, de-duplicated), and scalars take the nearer value when present.
  _PartialConfig overlay(_PartialConfig nearer) {
    final mergedToggles = <String, bool>{...ruleToggles, ...nearer.ruleToggles};

    final mergedIgnores = <String>[...ignoreGlobs];
    for (final glob in nearer.ignoreGlobs) {
      if (!mergedIgnores.contains(glob)) mergedIgnores.add(glob);
    }

    // layers merge per name; boundaries merge per importing layer (nearer wins).
    final mergedBoundaries = <String, LayerBoundary>{
      for (final b in boundaries) b.from: b,
      for (final b in nearer.boundaries) b.from: b,
    };

    return _PartialConfig(
      layers: {...layers, ...nearer.layers},
      boundaries: mergedBoundaries.values.toList(),
      ruleToggles: mergedToggles,
      ignoreGlobs: mergedIgnores,
      sourceDirs: nearer.sourceDirs ?? sourceDirs,
      updateCheck: nearer.updateCheck ?? updateCheck,
      includeA11y: nearer.includeA11y ?? includeA11y,
      autoUpdate: nearer.autoUpdate ?? autoUpdate,
      requiredVersion: nearer.requiredVersion ?? requiredVersion,
      profile: nearer.profile ?? profile,
      strictBaseline: nearer.strictBaseline ?? strictBaseline,
      cache: nearer.cache ?? cache,
      skipBoilerplate: nearer.skipBoilerplate ?? skipBoilerplate,
      boilerplateMethods: _union(boilerplateMethods, nearer.boilerplateMethods),
      reservedAnnotations: _union(
        reservedAnnotations,
        nearer.reservedAnnotations,
      ),
      assertionFunctions: _union(assertionFunctions, nearer.assertionFunctions),
    );
  }

  static List<String> _union(List<String> a, List<String> b) => [
    ...a,
    for (final x in b)
      if (!a.contains(x)) x,
  ];

  /// Resolves the merged layers into an immutable [LoamConfig], applying the
  /// Zero-Config defaults for any field left unset.
  LoamConfig materialize() => LoamConfig(
    ruleToggles: Map.unmodifiable(ruleToggles),
    ignoreGlobs: List.unmodifiable(ignoreGlobs),
    sourceDirs: sourceDirs ?? kDefaultSourceDirs,
    updateCheck: updateCheck ?? true,
    includeA11y: includeA11y ?? true,
    autoUpdate: autoUpdate ?? true,
    requiredVersion: requiredVersion,
    profile: profile,
    strictBaseline: strictBaseline ?? false,
    cache: cache ?? true,
    skipBoilerplate: skipBoilerplate ?? true,
    boilerplateMethods: List.unmodifiable(boilerplateMethods),
    reservedAnnotations: List.unmodifiable(reservedAnnotations),
    assertionFunctions: List.unmodifiable(assertionFunctions),
    layers: Map.unmodifiable(layers),
    boundaries: List.unmodifiable(boundaries),
  );
}
