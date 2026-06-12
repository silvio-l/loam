import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Known codegen generator package IDs detected in `dev_dependencies`.
const _knownGenerators = {
  'build_runner',
  'freezed',
  'hive_generator',
  'injectable_generator',
  'json_serializable',
  'mobx_codegen',
  'retrofit_generator',
  'riverpod_generator',
  'source_gen',
};

/// Read-only value object derived from a project's `pubspec.yaml`.
///
/// Carries detected codegen [detectedGenerators], [isFlutter] and
/// [isPublishable]. Derived deterministically: the same `pubspec.yaml`
/// always produces the same [StackProfile] (Invariant 5 — reproducibility).
///
/// **Never** makes suppression decisions — purely diagnostic. Feeds the
/// `stack: …` diagnostic line in `loam scan` output and future registry
/// priming. Suppression logic must remain at the Element-Model level
/// (Invariant 1 — semantics before syntax).
class StackProfile {
  /// Creates a [StackProfile] with the given fields.
  const StackProfile({
    required this.detectedGenerators,
    required this.isFlutter,
    required this.isPublishable,
  });

  /// Creates an empty profile with conservative defaults.
  ///
  /// Used when `pubspec.yaml` is missing, broken, or empty. [isPublishable]
  /// defaults to `true` — unknown publishability is treated as publishable
  /// (the App-vs-Package distinction is the most important FP class; erring
  /// towards publishable avoids suppressing real findings).
  const StackProfile.empty()
    : detectedGenerators = const {},
      isFlutter = false,
      isPublishable = true;

  /// Codegen generator IDs detected in `dev_dependencies`, e.g.
  /// `{'riverpod_generator', 'freezed', 'json_serializable'}`.
  final Set<String> detectedGenerators;

  /// `true` when `flutter` appears as a direct dependency (Flutter project).
  final bool isFlutter;

  /// `true` when `publish_to` is absent or not set to `none`.
  ///
  /// Conservative default: absent or unparseable `publish_to` → `true`.
  /// The App-vs-Package FP class is guarded downstream; the profile itself
  /// should never suppress findings based on publishability.
  final bool isPublishable;

  /// Parses `pubspec.yaml` at [projectRoot] and returns a [StackProfile].
  ///
  /// Defensive: a missing, unreadable, or malformed `pubspec.yaml` returns
  /// [StackProfile.empty()] instead of throwing. This keeps [ProjectLoader]
  /// crash-free even on unusual or partially set-up project layouts.
  static StackProfile fromProjectRoot(String projectRoot) {
    try {
      final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));
      if (!pubspecFile.existsSync()) return const StackProfile.empty();
      final content = pubspecFile.readAsStringSync();
      if (content.trim().isEmpty) return const StackProfile.empty();
      final dynamic raw = loadYaml(content);
      if (raw is! Map) return const StackProfile.empty();
      return _fromYaml(raw);
    } catch (_) {
      return const StackProfile.empty();
    }
  }

  static StackProfile _fromYaml(Map<dynamic, dynamic> yaml) {
    // isFlutter: 'flutter' must appear in [dependencies].
    final dynamic deps = yaml['dependencies'];
    final isFlutter = deps is Map && deps.containsKey('flutter');

    // isPublishable: true unless publish_to is explicitly 'none'.
    // Conservative: absent or non-string → publishable.
    final dynamic publishTo = yaml['publish_to'];
    final isPublishable = publishTo != 'none';

    // detectedGenerators: subset of _knownGenerators present in dev_dependencies.
    final dynamic devDeps = yaml['dev_dependencies'];
    final detected = <String>{};
    if (devDeps is Map) {
      for (final id in _knownGenerators) {
        if (devDeps.containsKey(id)) detected.add(id);
      }
    }

    return StackProfile(
      detectedGenerators: Set.unmodifiable(detected),
      isFlutter: isFlutter,
      isPublishable: isPublishable,
    );
  }
}
