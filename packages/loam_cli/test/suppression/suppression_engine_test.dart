@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:loam/src/suppression/suppression_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Finding _finding({
  required String filePath,
  String ruleId = 'unused-public-exports',
}) {
  return Finding(
    ruleId: ruleId,
    severity: Severity.warning,
    filePath: filePath,
    line: 1,
    message: 'test finding',
    fingerprint: 'fp-${filePath.hashCode}',
  );
}

/// Returns an absolute path by joining [root] with [relative].
String _abs(String root, String relative) => p.join(root, relative);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Use a stable fake project root for unit tests (no disk I/O needed).
  const fakeRoot = '/fake/project';

  // ---------------------------------------------------------------------------
  // AC1 + AC2: Glob loading and matching
  // ---------------------------------------------------------------------------

  group('SuppressionEngine.filter — glob suppression', () {
    test('returns all findings unchanged when ignoreGlobs is empty', () {
      final config = const LoamConfig.defaults();
      final findings = [
        _finding(filePath: _abs(fakeRoot, 'lib/foo.dart')),
        _finding(filePath: _abs(fakeRoot, 'test/bar.dart')),
      ];

      final result = SuppressionEngine.filter(findings, config, fakeRoot);

      expect(result, hasLength(2));
    });

    test('removes findings whose file matches an ignore glob', () {
      final config = LoamConfig(
        ruleToggles: const {},
        ignoreGlobs: const ['test/**'],
      );
      final kept = _finding(filePath: _abs(fakeRoot, 'lib/foo.dart'));
      final suppressed = _finding(
        filePath: _abs(fakeRoot, 'test/fixtures/bar.dart'),
      );

      final result = SuppressionEngine.filter(
        [kept, suppressed],
        config,
        fakeRoot,
      );

      expect(result, hasLength(1));
      expect(result.first.filePath, equals(kept.filePath));
    });

    test('keeps findings in files NOT matched by any glob', () {
      final config = LoamConfig(
        ruleToggles: const {},
        ignoreGlobs: const ['test/fixtures/**'],
      );
      final kept1 = _finding(filePath: _abs(fakeRoot, 'lib/a.dart'));
      final kept2 = _finding(filePath: _abs(fakeRoot, 'lib/b.dart'));
      final suppressed = _finding(
        filePath: _abs(fakeRoot, 'test/fixtures/stub.dart'),
      );

      final result = SuppressionEngine.filter(
        [kept1, suppressed, kept2],
        config,
        fakeRoot,
      );

      expect(result, hasLength(2));
      expect(
        result.map((f) => f.filePath),
        containsAll([kept1.filePath, kept2.filePath]),
      );
      expect(
        result.map((f) => f.filePath),
        isNot(contains(suppressed.filePath)),
      );
    });

    test('multiple globs: finding is removed when matched by ANY glob', () {
      final config = LoamConfig(
        ruleToggles: const {},
        ignoreGlobs: const ['test/**', 'tool/**'],
      );
      final fromTest = _finding(
        filePath: _abs(fakeRoot, 'test/some_test.dart'),
      );
      final fromTool = _finding(filePath: _abs(fakeRoot, 'tool/gen.dart'));
      final kept = _finding(filePath: _abs(fakeRoot, 'lib/ok.dart'));

      final result = SuppressionEngine.filter(
        [fromTest, fromTool, kept],
        config,
        fakeRoot,
      );

      expect(result, hasLength(1));
      expect(result.first.filePath, equals(kept.filePath));
    });

    test('glob with ** matches nested directories', () {
      final config = LoamConfig(
        ruleToggles: const {},
        ignoreGlobs: const ['test/fixtures/**'],
      );
      final deep = _finding(
        filePath: _abs(
          fakeRoot,
          'test/fixtures/unused_exports_fixture/lib/foo.dart',
        ),
      );
      final shallow = _finding(filePath: _abs(fakeRoot, 'test/bar.dart'));

      final result = SuppressionEngine.filter(
        [deep, shallow],
        config,
        fakeRoot,
      );

      // deep is suppressed; shallow is not matched by test/fixtures/**
      expect(result, hasLength(1));
      expect(result.first.filePath, equals(shallow.filePath));
    });

    test(
      'order of non-suppressed findings is preserved (deterministic, Invariant 5)',
      () {
        final config = LoamConfig(
          ruleToggles: const {},
          ignoreGlobs: const ['test/**'],
        );
        final f1 = _finding(filePath: _abs(fakeRoot, 'lib/a.dart'));
        final f2 = _finding(filePath: _abs(fakeRoot, 'lib/b.dart'));
        final f3 = _finding(filePath: _abs(fakeRoot, 'lib/c.dart'));
        final suppressed = _finding(filePath: _abs(fakeRoot, 'test/stub.dart'));

        final result = SuppressionEngine.filter(
          [f1, suppressed, f2, f3],
          config,
          fakeRoot,
        );

        expect(result, hasLength(3));
        expect(result[0].filePath, equals(f1.filePath));
        expect(result[1].filePath, equals(f2.filePath));
        expect(result[2].filePath, equals(f3.filePath));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AC4: ignore-Globs do NOT change rulesetVersion
  // ---------------------------------------------------------------------------

  group('rulesetVersion is NOT affected by ignore globs', () {
    test(
      'rulesetVersionForConfig is identical with and without ignore globs',
      () {
        const configNoGlobs = LoamConfig.defaults();
        final configWithGlobs = LoamConfig(
          ruleToggles: const {},
          ignoreGlobs: const ['test/**', 'tool/**'],
        );

        final versionNoGlobs = AnalysisRunner.rulesetVersionForConfig(
          configNoGlobs,
        );
        final versionWithGlobs = AnalysisRunner.rulesetVersionForConfig(
          configWithGlobs,
        );

        expect(
          versionWithGlobs,
          equals(versionNoGlobs),
          reason: 'ignore globs must not affect rulesetVersion',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AC3 + AC5: Integration via AnalysisRunner — suppression before sort/baseline/gate
  // ---------------------------------------------------------------------------

  group('AnalysisRunner integration — ignore globs suppress findings end-to-end', () {
    // The unused_exports_fixture produces real findings.
    // We confirm that ignoring its lib/** path removes those findings.
    final fixturePath = p.normalize(
      p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'unused_exports_fixture',
      ),
    );

    test('runner with no ignore globs produces findings from fixture', () async {
      final runner = AnalysisRunner();
      final findings = await runner.run(fixturePath);
      expect(
        findings,
        isNotEmpty,
        reason:
            'fixture must have findings for the suppression test to be meaningful',
      );
    });

    test(
      'runner with ignore glob covering all lib files suppresses those findings',
      () async {
        final config = LoamConfig(
          ruleToggles: const {},
          ignoreGlobs: const ['lib/**'],
        );
        final runner = AnalysisRunner(config: config);
        final findings = await runner.run(fixturePath);

        // All findings from the unused_exports_fixture are in lib/; suppressing
        // lib/** must leave 0 findings from that source.
        for (final f in findings) {
          final rel = p.relative(f.filePath, from: fixturePath);
          expect(
            rel.startsWith('lib/'),
            isFalse,
            reason:
                'finding from lib/ should have been suppressed: ${f.filePath}',
          );
        }
      },
    );

    test('runner with unrelated ignore glob leaves findings intact', () async {
      final configNoGlobs = AnalysisRunner();
      final configUnrelated = AnalysisRunner(
        config: LoamConfig(
          ruleToggles: const {},
          ignoreGlobs: const ['does_not_exist/**'],
        ),
      );

      final findingsNoGlobs = await configNoGlobs.run(fixturePath);
      final findingsUnrelated = await configUnrelated.run(fixturePath);

      expect(
        findingsUnrelated.length,
        equals(findingsNoGlobs.length),
        reason: 'unrelated glob must not suppress any finding',
      );
    });

    test(
      'suppression is deterministic: two runs with same config yield identical findings (Invariant 5)',
      () async {
        final config = LoamConfig(
          ruleToggles: const {},
          ignoreGlobs: const ['test/**'],
        );
        final runner = AnalysisRunner(config: config);

        final run1 = await runner.run(fixturePath);
        final run2 = await runner.run(fixturePath);

        expect(run1.length, equals(run2.length));
        for (var i = 0; i < run1.length; i++) {
          expect(run1[i].fingerprint, equals(run2[i].fingerprint));
          expect(run1[i].filePath, equals(run2[i].filePath));
        }
      },
    );
  });
}
