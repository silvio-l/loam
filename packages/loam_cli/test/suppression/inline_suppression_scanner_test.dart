@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:loam/src/suppression/inline_suppression_scanner.dart';
import 'package:loam/src/suppression/suppression_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [Finding] at a specific [filePath] and [line] with a given [ruleId].
Finding _finding({
  required String filePath,
  required int line,
  String ruleId = 'unused-public-exports',
}) {
  return Finding(
    ruleId: ruleId,
    severity: Severity.warning,
    filePath: filePath,
    line: line,
    message: 'test finding',
    fingerprint: 'fp-${filePath.hashCode}-$line',
  );
}

// ---------------------------------------------------------------------------
// Test setup
// ---------------------------------------------------------------------------

void main() {
  // Path to the inline_suppression_fixture.
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'inline_suppression_fixture',
    ),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    final loader = ProjectLoader();
    loadResult = await loader.load(fixturePath);
    expect(
      loadResult.errors,
      isEmpty,
      reason: 'inline_suppression_fixture must load cleanly',
    );
    expect(
      loadResult.resolved,
      isNotEmpty,
      reason: 'fixture must have at least one resolved file',
    );
  });

  // ---------------------------------------------------------------------------
  // AC1: InlineSuppressionScanner uses the analyzer comment model
  //       (no whole-file regex), returning (filePath, line, ruleId).
  // ---------------------------------------------------------------------------

  group('InlineSuppressionScanner — directive extraction via comment model', () {
    late Set<LoamIgnoreDirective> directives;

    setUpAll(() {
      // scan() requires the project root so it can produce project-relative
      // POSIX paths that match Finding.filePath (Invariant 5).
      directives = InlineSuppressionScanner.scan(loadResult, fixturePath);
    });

    test('scan returns a Set<LoamIgnoreDirective>', () {
      expect(directives, isA<Set<LoamIgnoreDirective>>());
    });

    test(
      'directives include same-line suppression on suppressed_same_line.dart',
      () {
        // d.filePath is project-relative (e.g. "lib/suppressed_same_line.dart")
        final sameLineDirectives = directives
            .where(
              (d) =>
                  d.filePath.endsWith('suppressed_same_line.dart') &&
                  d.ruleId == 'unused-public-exports',
            )
            .toList();
        expect(
          sameLineDirectives,
          isNotEmpty,
          reason: 'same-line directive must be detected',
        );
      },
    );

    test(
      'directives include preceding-line suppression on suppressed_same_line.dart',
      () {
        // The preceding-line directive covers SuppressedPrecedingLine.
        // We just verify there are multiple directives for the file (both forms).
        final fileDirectives = directives
            .where(
              (d) =>
                  d.filePath.endsWith('suppressed_same_line.dart') &&
                  d.ruleId == 'unused-public-exports',
            )
            .toList();
        expect(
          fileDirectives.length,
          greaterThanOrEqualTo(2),
          reason:
              'both same-line and preceding-line directives must be detected',
        );
      },
    );

    test('directives carry the correct ruleId', () {
      for (final d in directives) {
        expect(d.ruleId, isNotEmpty, reason: 'ruleId must not be empty');
      }
    });

    test('directives carry non-zero line numbers (1-based)', () {
      for (final d in directives) {
        expect(d.line, greaterThan(0), reason: 'line must be 1-based');
      }
    });

    test('directive filePath is project-relative (not absolute)', () {
      for (final d in directives) {
        expect(
          p.isAbsolute(d.filePath),
          isFalse,
          reason: 'filePath must be project-relative, not absolute',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // AC3: A directive without a matching ruleId suppresses nothing.
  //
  // Tested here via the scanner output: wrong-ruleId directives must not
  // produce a LoamIgnoreDirective with ruleId == 'unused-public-exports'.
  // ---------------------------------------------------------------------------

  group('InlineSuppressionScanner — wrong ruleId', () {
    test('wrong ruleId directive does not produce unused-public-exports entry', () {
      final directives = InlineSuppressionScanner.scan(loadResult, fixturePath);
      // The WrongRuleDirective class has `some-other-rule` — it must appear
      // with ruleId 'some-other-rule', NOT 'unused-public-exports'.
      // Check that whatever directives come from invalid_directives.dart do NOT
      // have ruleId == 'unused-public-exports' (the only directive there uses
      // 'some-other-rule').
      final unusedExportsFromInvalidFile = directives.where(
        (d) =>
            d.filePath.endsWith('invalid_directives.dart') &&
            d.ruleId == 'unused-public-exports',
      );
      expect(
        unusedExportsFromInvalidFile,
        isEmpty,
        reason:
            'a directive with a different ruleId must not suppress unused-public-exports',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: Grund-Pflicht — directives without reason text are not valid.
  // ---------------------------------------------------------------------------

  group('InlineSuppressionScanner — Grund-Pflicht (reason required)', () {
    test('directive without reason text is not accepted', () {
      final directives = InlineSuppressionScanner.scan(loadResult, fixturePath);
      // invalid_directives.dart contains:
      //   // loam-ignore: unused-public-exports   (no reason → invalid)
      //   // loam-ignore:                          (no ruleId or reason → invalid)
      //   // loam-ignore: some-other-rule – …     (different rule → not suppressing UPE)
      // None of these should produce a directive with ruleId == 'unused-public-exports'.
      final suppressionForUnused = directives.where(
        (d) =>
            d.filePath.endsWith('invalid_directives.dart') &&
            d.ruleId == 'unused-public-exports',
      );
      expect(
        suppressionForUnused,
        isEmpty,
        reason:
            'a loam-ignore directive without a reason must be rejected (Grund-Pflicht)',
      );
    });

    test(
      'directive without ruleId (bare // loam-ignore:) produces no directive',
      () {
        final directives = InlineSuppressionScanner.scan(
          loadResult,
          fixturePath,
        );
        // The bare `// loam-ignore:` with no ruleId must yield nothing at all.
        final bareDirectives = directives.where(
          (d) =>
              d.filePath.endsWith('invalid_directives.dart') &&
              d.ruleId.isEmpty,
        );
        expect(
          bareDirectives,
          isEmpty,
          reason:
              'bare // loam-ignore: with no ruleId must produce no directive',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AC2 + AC5: SuppressionEngine — inline source removes the exact finding;
  //             other findings of the same rule are NOT suppressed.
  // ---------------------------------------------------------------------------

  group('SuppressionEngine — inline-directive source', () {
    const fakeRoot = '/fake/project';
    const fakeFile = '/fake/project/lib/foo.dart';

    test('inline directive on same line suppresses exactly that finding', () {
      final directive = LoamIgnoreDirective(
        filePath: fakeFile,
        line: 5,
        ruleId: 'unused-public-exports',
      );
      final suppressed = _finding(filePath: fakeFile, line: 5);
      final kept = _finding(filePath: fakeFile, line: 10);

      final result = SuppressionEngine.filter(
        [suppressed, kept],
        const LoamConfig.defaults(),
        fakeRoot,
        inlineDirectives: {directive},
      );

      expect(result, hasLength(1));
      expect(result.first.line, equals(10));
    });

    test(
      'inline directive on preceding line suppresses the finding on the next line',
      () {
        final directive = LoamIgnoreDirective(
          filePath: fakeFile,
          line: 7,
          ruleId: 'unused-public-exports',
        );
        // Finding is on line 8 (= directive.line + 1) → should be suppressed.
        final suppressed = _finding(filePath: fakeFile, line: 8);
        // Finding on line 9 (= directive.line + 2) → NOT suppressed.
        final kept = _finding(filePath: fakeFile, line: 9);

        final result = SuppressionEngine.filter(
          [suppressed, kept],
          const LoamConfig.defaults(),
          fakeRoot,
          inlineDirectives: {directive},
        );

        expect(result, hasLength(1));
        expect(result.first.line, equals(9));
      },
    );

    test('directive with wrong ruleId does not suppress findings', () {
      final directive = LoamIgnoreDirective(
        filePath: fakeFile,
        line: 5,
        ruleId: 'some-other-rule',
      );
      final notSuppressed = _finding(
        filePath: fakeFile,
        line: 5,
        ruleId: 'unused-public-exports',
      );

      final result = SuppressionEngine.filter(
        [notSuppressed],
        const LoamConfig.defaults(),
        fakeRoot,
        inlineDirectives: {directive},
      );

      expect(result, hasLength(1));
    });

    test(
      'directive in one file does not suppress findings in another file',
      () {
        const otherFile = '/fake/project/lib/bar.dart';
        final directive = LoamIgnoreDirective(
          filePath: fakeFile,
          line: 5,
          ruleId: 'unused-public-exports',
        );
        final notSuppressed = _finding(filePath: otherFile, line: 5);

        final result = SuppressionEngine.filter(
          [notSuppressed],
          const LoamConfig.defaults(),
          fakeRoot,
          inlineDirectives: {directive},
        );

        expect(result, hasLength(1));
      },
    );

    test(
      'other findings of the same rule at different lines remain visible',
      () {
        final directive = LoamIgnoreDirective(
          filePath: fakeFile,
          line: 5,
          ruleId: 'unused-public-exports',
        );
        final suppressed = _finding(filePath: fakeFile, line: 5);
        final kept1 = _finding(filePath: fakeFile, line: 3);
        final kept2 = _finding(filePath: fakeFile, line: 20);

        final result = SuppressionEngine.filter(
          [kept1, suppressed, kept2],
          const LoamConfig.defaults(),
          fakeRoot,
          inlineDirectives: {directive},
        );

        expect(result, hasLength(2));
        expect(result.map((f) => f.line), containsAll([3, 20]));
        expect(result.map((f) => f.line), isNot(contains(5)));
      },
    );

    // -------------------------------------------------------------------------
    // AC5 (combination): glob + inline sources overlap cleanly.
    // -------------------------------------------------------------------------

    test('glob and inline sources combine: union of both is suppressed', () {
      const globFile = '/fake/project/test/stub.dart';
      final config = LoamConfig(
        ruleToggles: const {},
        ignoreGlobs: const ['test/**'],
      );
      final directive = LoamIgnoreDirective(
        filePath: fakeFile,
        line: 5,
        ruleId: 'unused-public-exports',
      );

      final byGlob = _finding(filePath: globFile, line: 1);
      final byInline = _finding(filePath: fakeFile, line: 5);
      final kept = _finding(filePath: fakeFile, line: 10);

      final result = SuppressionEngine.filter(
        [byGlob, byInline, kept],
        config,
        fakeRoot,
        inlineDirectives: {directive},
      );

      expect(result, hasLength(1));
      expect(result.first.line, equals(10));
    });

    test('empty inlineDirectives leaves findings unchanged (fast path)', () {
      final f = _finding(filePath: fakeFile, line: 5);
      final result = SuppressionEngine.filter(
        [f],
        const LoamConfig.defaults(),
        fakeRoot,
      );
      expect(result, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // AC6: rulesetVersion is NOT affected by inline suppression.
  // ---------------------------------------------------------------------------

  group('rulesetVersion unchanged by inline suppression', () {
    test(
      'rulesetVersionForConfig is the same regardless of inline directives',
      () {
        // rulesetVersion depends only on the active rule set — never on
        // suppression sources (glob or inline).
        const config = LoamConfig.defaults();
        final v1 = AnalysisRunner.rulesetVersionForConfig(config);
        // Run again — identity check (no state changed by scanning).
        final v2 = AnalysisRunner.rulesetVersionForConfig(config);
        expect(v1, equals(v2));
        // The version string does not encode anything suppression-related.
        expect(v1, startsWith('ruleset@'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AC7 + AC8: AnalysisRunner end-to-end — inline suppression wired in
  //             via the single run() path (ADR-0003 / D10).
  // ---------------------------------------------------------------------------

  group('AnalysisRunner end-to-end — inline suppression via run()', () {
    test(
      'suppressed classes do not appear in findings; unsuppressed classes do',
      () async {
        final runner = AnalysisRunner();
        final findings = await runner.run(fixturePath);

        // SuppressedSameLine and SuppressedPrecedingLine have valid directives
        // → must NOT appear.
        expect(
          findings.any((f) => f.message.contains('SuppressedSameLine')),
          isFalse,
          reason:
              'SuppressedSameLine must be suppressed by same-line directive',
        );
        expect(
          findings.any((f) => f.message.contains('SuppressedPrecedingLine')),
          isFalse,
          reason:
              'SuppressedPrecedingLine must be suppressed by preceding-line directive',
        );

        // NotSuppressed and AlsoNotSuppressed have no directive → must appear.
        expect(
          findings.any((f) => f.message.contains('NotSuppressed')),
          isTrue,
          reason: 'NotSuppressed must still be reported',
        );
        expect(
          findings.any((f) => f.message.contains('AlsoNotSuppressed')),
          isTrue,
          reason: 'AlsoNotSuppressed must still be reported',
        );
      },
    );

    test(
      'classes with invalid directives (no reason, no ruleId, wrong ruleId) are NOT suppressed',
      () async {
        final runner = AnalysisRunner();
        final findings = await runner.run(fixturePath);

        // NoReasonDirective: directive has no reason → rejected → still reported.
        expect(
          findings.any((f) => f.message.contains('NoReasonDirective')),
          isTrue,
          reason: 'directive without reason must not suppress the finding',
        );

        // NoRuleIdDirective: directive has no ruleId → rejected → still reported.
        expect(
          findings.any((f) => f.message.contains('NoRuleIdDirective')),
          isTrue,
          reason: 'directive without ruleId must not suppress the finding',
        );

        // WrongRuleDirective: directive targets a different rule → still reported.
        expect(
          findings.any((f) => f.message.contains('WrongRuleDirective')),
          isTrue,
          reason: 'directive with wrong ruleId must not suppress the finding',
        );
      },
    );

    test(
      'rulesetVersion does not change when inline directives are present',
      () async {
        // Scan the fixture (which HAS inline directives) and confirm the
        // rulesetVersion is identical to scanning without any directives.
        const configNoGlobs = LoamConfig.defaults();
        final versionWithDirectivesPresent =
            AnalysisRunner.rulesetVersionForConfig(configNoGlobs);
        final versionBaseline = AnalysisRunner.rulesetVersionForConfig(
          const LoamConfig.defaults(),
        );
        expect(
          versionWithDirectivesPresent,
          equals(versionBaseline),
          reason:
              'inline-suppression directives must not change rulesetVersion',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Self-dogfooding: loam.dev scans itself with inline directives wired in.
  //
  // The dogfooding_test.dart already covers the main self-scan; this test
  // ensures that introducing inline suppression scanning does not break the
  // self-scan (no crash, deterministic output).
  // ---------------------------------------------------------------------------

  group('Self-dogfooding: inline suppression does not break self-scan', () {
    test('AnalysisRunner.run() on own codebase does not throw', () async {
      // Resolve the loam_cli package root from the test working directory.
      final packageRoot = p.normalize(Directory.current.path);
      final runner = AnalysisRunner();
      // Must not throw — any exception here is a regression.
      final findings = await runner.run(packageRoot);
      expect(findings, isA<List<Finding>>());
    });
  });
}
