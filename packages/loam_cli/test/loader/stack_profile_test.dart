@TestOn('vm')
library;

/// Tests for [StackProfile] (AC5 invarianz-test + AC6 unit-tests).
///
/// AC5 — Invarianz-Test:
///   Running [UnusedPublicExportsRule] on a [ProjectLoadResult] with a
///   populated [StackProfile] vs. an empty [StackProfile] yields an
///   **identical** Finding set. This proves Invariant 1 (semantics remain at
///   the Element-Model level; pubspec only primes diagnostics, never
///   suppresses).
///
/// AC6 — Unit-Tests:
///   [StackProfile.fromProjectRoot] against a real fixture pubspec (generators/
///   Flutter/Publishability) + the defensive error path (empty profile, no
///   crash).
import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/unused_public_exports_rule.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Resolve fixture paths relative to CWD (packages/loam_cli/ when run with
  // `dart test`).
  final unusedExportsFixture = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    ),
  );

  // ---------------------------------------------------------------------------
  // AC6: Unit-Tests — StackProfile.fromProjectRoot
  // ---------------------------------------------------------------------------

  // Path to a publishable fixture (no publish_to: none) for isPublishable tests.
  final publishablePkgFixture = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'publishable_pkg_fixture',
    ),
  );

  group('AC6: StackProfile.fromProjectRoot', () {
    // The publishable_pkg_fixture pubspec has no Flutter dep and no publish_to:
    // none → isFlutter=false, isPublishable=true.
    test('parses publishable_pkg_fixture/pubspec.yaml correctly', () {
      final profile = StackProfile.fromProjectRoot(publishablePkgFixture);

      expect(profile.isFlutter, isFalse, reason: 'no flutter dep in fixture');
      expect(
        profile.isPublishable,
        isTrue,
        reason: 'no publish_to: none in fixture → conservative default true',
      );
      // The fixture has no known codegen generators in dev_dependencies.
      expect(profile.detectedGenerators, isEmpty);
    });

    test('detects generators in a fixture pubspec with codegen entries', () {
      final dir = Directory.systemTemp.createTempSync('loam_stack_profile_');
      try {
        final pubspecFile = File(p.join(dir.path, 'pubspec.yaml'));
        pubspecFile.writeAsStringSync('''
name: test_pkg
version: 0.1.0
environment:
  sdk: ^3.0.0
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  build_runner: ^2.0.0
  freezed: ^2.0.0
  json_serializable: ^6.0.0
  riverpod_generator: ^2.0.0
''');

        final profile = StackProfile.fromProjectRoot(dir.path);

        expect(profile.isFlutter, isTrue);
        expect(
          profile.detectedGenerators,
          containsAll([
            'build_runner',
            'freezed',
            'json_serializable',
            'riverpod_generator',
          ]),
        );
        expect(profile.isPublishable, isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('isPublishable = false when publish_to: none', () {
      final dir = Directory.systemTemp.createTempSync('loam_stack_profile_');
      try {
        final pubspecFile = File(p.join(dir.path, 'pubspec.yaml'));
        pubspecFile.writeAsStringSync('''
name: app_pkg
publish_to: none
environment:
  sdk: ^3.0.0
''');

        final profile = StackProfile.fromProjectRoot(dir.path);
        expect(profile.isPublishable, isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('empty() when pubspec.yaml is missing — no crash', () {
      final profile = StackProfile.fromProjectRoot('/nonexistent/path/xyz');

      expect(profile.detectedGenerators, isEmpty);
      expect(profile.isFlutter, isFalse);
      expect(
        profile.isPublishable,
        isTrue,
        reason: 'conservative default: unknown ⇒ publishable',
      );
    });

    test('empty() when pubspec.yaml is empty — no crash', () {
      final dir = Directory.systemTemp.createTempSync('loam_stack_profile_');
      try {
        File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('');
        final profile = StackProfile.fromProjectRoot(dir.path);

        expect(profile.detectedGenerators, isEmpty);
        expect(profile.isFlutter, isFalse);
        expect(profile.isPublishable, isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('empty() when pubspec.yaml is broken YAML — no crash', () {
      final dir = Directory.systemTemp.createTempSync('loam_stack_profile_');
      try {
        File(
          p.join(dir.path, 'pubspec.yaml'),
        ).writeAsStringSync('{ broken: yaml: [unclosed');
        final profile = StackProfile.fromProjectRoot(dir.path);

        expect(profile.detectedGenerators, isEmpty);
        expect(profile.isFlutter, isFalse);
        expect(profile.isPublishable, isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // AC1 (via loader): ProjectLoadResult.stackProfile is populated by
  // ProjectLoader, not left as StackProfile.empty().
  // ---------------------------------------------------------------------------

  group('AC1: ProjectLoadResult carries stackProfile from loader', () {
    late ProjectLoadResult loadResult;

    setUpAll(() async {
      loadResult = await const ProjectLoader().load(unusedExportsFixture);
    });

    test('stackProfile is a StackProfile instance', () {
      expect(loadResult.stackProfile, isA<StackProfile>());
    });

    test('stackProfile is deterministic (same load ⇒ same profile)', () async {
      final second = await const ProjectLoader().load(unusedExportsFixture);
      expect(
        second.stackProfile.isFlutter,
        equals(loadResult.stackProfile.isFlutter),
      );
      expect(
        second.stackProfile.isPublishable,
        equals(loadResult.stackProfile.isPublishable),
      );
      expect(
        second.stackProfile.detectedGenerators,
        equals(loadResult.stackProfile.detectedGenerators),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC5: Invarianz-Test
  //
  // UnusedPublicExportsRule run on a ProjectLoadResult with a populated
  // StackProfile vs. one with an empty StackProfile yields an IDENTICAL
  // finding set. Proves Invariant 1: semantics at Element-Model, pubspec
  // only primes diagnostics.
  // ---------------------------------------------------------------------------

  group(
    'AC5: Invarianz-Test — UnusedPublicExportsRule is profile-agnostic',
    () {
      late ProjectLoadResult baseLoadResult;

      setUpAll(() async {
        baseLoadResult = await const ProjectLoader().load(unusedExportsFixture);
      });

      test('findings are identical with empty vs. rich StackProfile', () {
        final rule = UnusedPublicExportsRule(projectRoot: unusedExportsFixture);

        // Baseline: use the result as loaded (empty profile for this fixture).
        final findingsEmpty = rule.run(baseLoadResult);

        // Rich profile: manually inject a populated StackProfile into a new
        // ProjectLoadResult sharing the same resolved/error/partUnit data.
        final richProfile = StackProfile(
          detectedGenerators: const {'freezed', 'json_serializable'},
          isFlutter: true,
          isPublishable: false,
        );
        final loadResultWithProfile = ProjectLoadResult(
          resolved: baseLoadResult.resolved,
          errors: baseLoadResult.errors,
          partUnits: baseLoadResult.partUnits,
          stackProfile: richProfile,
        );
        final findingsRich = rule.run(loadResultWithProfile);

        // Fingerprint sets must be identical regardless of profile.
        expect(
          findingsRich.map((f) => f.fingerprint).toSet(),
          equals(findingsEmpty.map((f) => f.fingerprint).toSet()),
          reason:
              'StackProfile must not influence rule findings '
              '(Invariant 1: semantics at Element-Model)',
        );

        // Also check message and filePath for completeness.
        expect(
          findingsRich.map((f) => '${f.filePath}:${f.line}').toSet(),
          equals(findingsEmpty.map((f) => '${f.filePath}:${f.line}').toSet()),
        );
      });
    },
  );
}
