/// The parsed configuration from a project's `loam.yaml` file.
///
/// [LoamConfig] is an immutable value object. It carries:
/// - [ruleToggles]: per-rule on/off switches (`ruleId → bool`).
/// - [ignoreGlobs]: project-relative glob patterns for path suppression
///   (placeholder — glob matching is implemented in issue 02).
///
/// Zero-Config is the Normalfall: [LoamConfig.defaults] returns an empty
/// config so that `loam` works out-of-the-box without a `loam.yaml`.
class LoamConfig {
  /// Creates a [LoamConfig] with explicit [ruleToggles] and [ignoreGlobs].
  const LoamConfig({required this.ruleToggles, required this.ignoreGlobs});

  /// Returns the zero-config default: all rules enabled, no ignore globs.
  const LoamConfig.defaults() : ruleToggles = const {}, ignoreGlobs = const [];

  /// Per-rule toggle map. `true` = enabled (default), `false` = disabled.
  ///
  /// Rules absent from this map default to enabled.
  final Map<String, bool> ruleToggles;

  /// Project-relative glob patterns for path suppression (issue 02).
  ///
  /// Placeholder — stored on the model now, matching logic comes in issue 02.
  final List<String> ignoreGlobs;

  /// Returns `true` when [ruleId] is explicitly disabled in [ruleToggles].
  bool isRuleDisabled(String ruleId) => ruleToggles[ruleId] == false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoamConfig &&
          _mapsEqual(ruleToggles, other.ruleToggles) &&
          _listsEqual(ignoreGlobs, other.ignoreGlobs);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ruleToggles.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(ignoreGlobs),
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
