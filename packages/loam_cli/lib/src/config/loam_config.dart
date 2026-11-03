import 'package:pub_semver/pub_semver.dart';

import '../rules/rule_profile.dart';
import 'architecture_config.dart';

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
/// - [includeA11y]: whether accessibility-category rules are included in
///   `loam scan` (`true` by default). Corresponds to `a11y: false` in
///   `loam.yaml` and the `--no-a11y` CLI flag on `loam scan`.
/// - [autoUpdate]: whether loam may install new versions by itself
///   (`auto_update`, `true` by default).
/// - [requiredVersion]: the loam version pin (`required_version`), or `null`.
/// - [cache]: whether the analyzer's summary store is kept on disk between
///   runs (`cache`, `true` by default).
///
/// Zero-Config is the Normalfall: [LoamConfig.defaults] returns an empty
/// config so that `loam` works out-of-the-box without a `loam.yaml`.
class LoamConfig {
  /// Creates a [LoamConfig] with explicit [ruleToggles], [ignoreGlobs],
  /// [sourceDirs], [updateCheck] and [includeA11y].
  const LoamConfig({
    required this.ruleToggles,
    required this.ignoreGlobs,
    this.sourceDirs = kDefaultSourceDirs,
    this.updateCheck = true,
    this.includeA11y = true,
    this.autoUpdate = true,
    this.requiredVersion,
    this.profile,
    this.strictBaseline = false,
    this.cache = true,
    this.skipBoilerplate = true,
    this.boilerplateMethods = const [],
    this.reservedAnnotations = const [],
    this.assertionFunctions = const [],
    this.layers = const {},
    this.boundaries = const [],
  });

  /// Returns the zero-config default: all rules enabled, no ignore globs,
  /// default source dirs, update check enabled, a11y included.
  const LoamConfig.defaults()
    : ruleToggles = const {},
      ignoreGlobs = const [],
      sourceDirs = kDefaultSourceDirs,
      updateCheck = true,
      includeA11y = true,
      autoUpdate = true,
      requiredVersion = null,
      profile = null,
      strictBaseline = false,
      cache = true,
      skipBoilerplate = true,
      boilerplateMethods = const [],
      reservedAnnotations = const [],
      assertionFunctions = const [],
      layers = const {},
      boundaries = const [];

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

  /// Whether accessibility-category rules are included in `loam scan`.
  ///
  /// Default is `true` (Zero-Config — a11y rules run in scan by default).
  /// Set to `false` via `a11y: false` in `loam.yaml` or `--no-a11y` on the
  /// `loam scan` CLI flag to exclude all accessibility rules from the scan.
  ///
  /// When `false`, accessibility rules are removed from the active registry
  /// before the runner is instantiated — they produce no findings, no side
  /// effects and no wasted computation (registry-level filter, not a
  /// post-filter on findings).
  final bool includeA11y;

  /// Whether loam may install a newer version of itself in the background.
  ///
  /// Corresponds to `auto_update: bool` in `loam.yaml` (default `true`).
  /// `false` keeps the once-a-day update notice but never installs anything;
  /// the `LOAM_NO_AUTO_UPDATE` environment variable does the same machine-wide.
  final bool autoUpdate;

  /// The loam versions this project accepts (`required_version` in
  /// `loam.yaml`, a pub version constraint such as `">=0.1.15 <0.2.0"` or an
  /// exact `"0.1.15"`), or `null` when the version is not pinned.
  ///
  /// A pinned project is never auto-updated. A running version outside the
  /// constraint prints a warning, and `loam gate` stops with exit code 78.
  final VersionConstraint? requiredVersion;

  /// Rule profile from `profile:` in `loam.yaml`; `null` when not set. Only
  /// `loam gate` reads it; resolve it with [RuleProfile.resolve].
  final RuleProfile? profile;

  /// Whether the analyzer keeps its summary store in `.dart_tool/loam/`
  /// between runs (`cache: bool` in `loam.yaml`, default `true`).
  ///
  /// `false` resolves from scratch on every run; `--no-cache` does the same
  /// for one invocation. The store never changes results, only run time.
  final bool cache;

  /// Whether `loam gate` (ratchet mode) fails when `baseline.json` holds stale
  /// entries — findings that no longer occur. Corresponds to
  /// `strict_baseline: bool` in `loam.yaml` (default `false`: stale entries are
  /// only reported); `--strict-baseline` / `--no-strict-baseline` on the
  /// command line override it.
  final bool strictBaseline;

  /// Whether `code-duplicates` skips the built-in boilerplate methods
  /// (`copyWith`, `==`, `hashCode`, `toString`, `toJson`/`toMap`,
  /// `fromJson`/`fromMap`, `props`). `code_duplicates.boilerplate` in
  /// `loam.yaml`, default `true`.
  final bool skipBoilerplate;

  /// Extra method names `code-duplicates` skips, matched by name only
  /// (`code_duplicates.boilerplate_methods`). Additive across config layers.
  final List<String> boilerplateMethods;

  /// Extra annotation names that mark a symbol as deliberately public for
  /// `unused-public-exports` (`unused_public_exports.annotations`). Additive
  /// across config layers.
  final List<String> reservedAnnotations;

  /// Extra function names that count as an assertion for
  /// `slop-assertion-free-test`
  /// (`slop_assertion_free_test.assertion_functions`), matched by name.
  /// Additive across config layers.
  final List<String> assertionFunctions;

  /// Architecture **Layers** from `layers:` in `loam.yaml`: layer name ->
  /// project-relative directory prefix. Empty when none are configured. Only
  /// `loam init` writes them (from detection); a run never re-detects.
  final Map<String, String> layers;

  /// **Boundaries** from `boundaries:` in `loam.yaml`: per importing layer the
  /// layers it must not import. Every name refers to a key of [layers].
  final List<LayerBoundary> boundaries;

  /// Returns `true` when [ruleId] is explicitly disabled in [ruleToggles].
  bool isRuleDisabled(String ruleId) => ruleToggles[ruleId] == false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoamConfig &&
          _mapsEqual(ruleToggles, other.ruleToggles) &&
          _listsEqual(ignoreGlobs, other.ignoreGlobs) &&
          _listsEqual(sourceDirs, other.sourceDirs) &&
          updateCheck == other.updateCheck &&
          includeA11y == other.includeA11y &&
          autoUpdate == other.autoUpdate &&
          cache == other.cache &&
          requiredVersion == other.requiredVersion &&
          profile == other.profile &&
          strictBaseline == other.strictBaseline &&
          skipBoilerplate == other.skipBoilerplate &&
          _listsEqual(boilerplateMethods, other.boilerplateMethods) &&
          _listsEqual(reservedAnnotations, other.reservedAnnotations) &&
          _listsEqual(assertionFunctions, other.assertionFunctions) &&
          _stringMapsEqual(layers, other.layers) &&
          _boundariesEqual(boundaries, other.boundaries);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ruleToggles.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(ignoreGlobs),
    Object.hashAll(sourceDirs),
    updateCheck,
    includeA11y,
    autoUpdate,
    cache,
    requiredVersion,
    profile,
    strictBaseline,
    skipBoilerplate,
    Object.hashAll(boilerplateMethods),
    Object.hashAll(reservedAnnotations),
    Object.hashAll(assertionFunctions),
    Object.hashAll(layers.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(boundaries),
  );

  static bool _stringMapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (b[key] != a[key]) return false;
    }
    return true;
  }

  static bool _boundariesEqual(List<LayerBoundary> a, List<LayerBoundary> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapsEqual(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (b[key] != a[key]) return false;
    }
    return true;
  }

  // Per-class equality helper; extracting a shared generic would require a new import and obscure the type specificity.
  static bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
