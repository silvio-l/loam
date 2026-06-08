/// The parsed configuration from a project's `loam.yaml` file.
///
/// [LoamConfig] is an immutable value object. It carries:
/// - [ruleToggles]: per-rule on/off switches (`ruleId → bool`).
/// - [ignoreGlobs]: project-relative glob patterns for path suppression
///   (placeholder — glob matching is implemented in issue 02).
/// - [updateCheck]: whether the update-availability check is enabled
///   repo-wide (`true` by default, `false` = opt-out for this project).
///
/// Zero-Config is the Normalfall: [LoamConfig.defaults] returns an empty
/// config so that `loam` works out-of-the-box without a `loam.yaml`.
class LoamConfig {
  /// Creates a [LoamConfig] with explicit [ruleToggles], [ignoreGlobs], and
  /// [updateCheck].
  const LoamConfig({
    required this.ruleToggles,
    required this.ignoreGlobs,
    this.updateCheck = true,
  });

  /// Returns the zero-config default: all rules enabled, no ignore globs,
  /// update check enabled.
  const LoamConfig.defaults()
    : ruleToggles = const {},
      ignoreGlobs = const [],
      updateCheck = true;

  /// Per-rule toggle map. `true` = enabled (default), `false` = disabled.
  ///
  /// Rules absent from this map default to enabled.
  final Map<String, bool> ruleToggles;

  /// Project-relative glob patterns for path suppression (issue 02).
  ///
  /// Placeholder — stored on the model now, matching logic comes in issue 02.
  final List<String> ignoreGlobs;

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
          updateCheck == other.updateCheck;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ruleToggles.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(ignoreGlobs),
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
