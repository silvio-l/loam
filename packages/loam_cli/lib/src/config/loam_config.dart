/// The default production-source directories the universal complexity scan
/// measures: hand-written, shipping Dart code.
///
/// `lib/` is every package's source; `bin/` holds executable entrypoints (CLI
/// tools, scripts that ship). Deliberately excludes `test/` and friends
/// (intentionally high complexity = noise), `example/`/`tool/` (demo/dev code)
/// and generated files (always excluded, can't be refactored). Override per
/// project via `source_dirs` in `loam.yaml`.
const List<String> kDefaultSourceDirs = ['lib', 'bin'];

/// The parsed configuration from a project's `loam.yaml` file.
///
/// [LoamConfig] is an immutable value object. It carries:
/// - [ruleToggles]: per-rule on/off switches (`ruleId → bool`).
/// - [ignoreGlobs]: project-relative glob patterns for path suppression
///   (placeholder — glob matching is implemented in issue 02).
/// - [sourceDirs]: top-level directories treated as production source for the
///   universal complexity scan (defaults to [kDefaultSourceDirs]).
/// - [updateCheck]: whether the update-availability check is enabled
///   repo-wide (`true` by default, `false` = opt-out for this project).
///
/// Zero-Config is the Normalfall: [LoamConfig.defaults] returns an empty
/// config so that `loam` works out-of-the-box without a `loam.yaml`.
class LoamConfig {
  /// Creates a [LoamConfig] with explicit [ruleToggles], [ignoreGlobs],
  /// [sourceDirs] and [updateCheck].
  const LoamConfig({
    required this.ruleToggles,
    required this.ignoreGlobs,
    this.sourceDirs = kDefaultSourceDirs,
    this.updateCheck = true,
  });

  /// Returns the zero-config default: all rules enabled, no ignore globs,
  /// default source dirs, update check enabled.
  const LoamConfig.defaults()
    : ruleToggles = const {},
      ignoreGlobs = const [],
      sourceDirs = kDefaultSourceDirs,
      updateCheck = true;

  /// Per-rule toggle map. `true` = enabled (default), `false` = disabled.
  ///
  /// Rules absent from this map default to enabled.
  final Map<String, bool> ruleToggles;

  /// Project-relative glob patterns for path suppression (issue 02).
  ///
  /// Placeholder — stored on the model now, matching logic comes in issue 02.
  final List<String> ignoreGlobs;

  /// Top-level directories treated as production source for the universal
  /// complexity scan (`complexity-hotspots`, `loam health`).
  ///
  /// Corresponds to `source_dirs:` in `loam.yaml`. Defaults to
  /// [kDefaultSourceDirs] (`lib`, `bin`). Generated files are always excluded
  /// regardless of this setting. Structural rules that are inherently a `lib/`
  /// concept (`circular-dependencies`, `unused-public-exports`) are unaffected.
  final List<String> sourceDirs;

  /// Whether the update-availability check is enabled for this project.
  ///
  /// Corresponds to `update_check: bool` in `loam.yaml`.
  /// Default is `true` (Zero-Config). Set to `false` to opt out repo-wide.
  /// This is the config-layer opt-out in the precedence chain:
  /// `--no-update-check` (CLI) > `LOAM_NO_UPDATE_CHECK` (env) >
  /// `update_check: false` (config) > default (on).
  final bool updateCheck;

  /// Returns `true` when [ruleId] is explicitly disabled in [ruleToggles].
  bool isRuleDisabled(String ruleId) => ruleToggles[ruleId] == false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoamConfig &&
          _mapsEqual(ruleToggles, other.ruleToggles) &&
          _listsEqual(ignoreGlobs, other.ignoreGlobs) &&
          _listsEqual(sourceDirs, other.sourceDirs) &&
          updateCheck == other.updateCheck;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ruleToggles.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(ignoreGlobs),
    Object.hashAll(sourceDirs),
    updateCheck,
  );

  static bool _mapsEqual(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (b[key] != a[key]) return false;
    }
    return true;
  }

  static bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
