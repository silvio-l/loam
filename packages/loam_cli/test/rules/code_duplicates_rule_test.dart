@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/duplicates/duplicate_code_collector.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/fingerprint.dart';
import 'package:loam/src/rules/code_duplicates_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'code_duplicates_fixture',
    ),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    final loader = ProjectLoader();
    loadResult = await loader.load(fixturePath);
    expect(loadResult.errors, isEmpty, reason: 'Fixture must load cleanly');
  });

  CodeDuplicatesRule makeRule() => CodeDuplicatesRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // AC: Rule interface contract
  // ---------------------------------------------------------------------------

  test('ruleId is code-duplicates', () {
    expect(makeRule().ruleId, 'code-duplicates');
  });

  test('severity of all findings is Severity.warning', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.severity, Severity.warning);
    }
  });

  // ---------------------------------------------------------------------------
  // AC: One Finding per cluster
  // ---------------------------------------------------------------------------

  test('emits at least one finding for the fixture (known duplicates)', () {
    final findings = makeRule().run(loadResult);
    expect(findings, isNotEmpty, reason: 'Fixture has duplicate code blocks');
  });

  test('no duplicate fingerprints — exactly one Finding per cluster', () {
    final findings = makeRule().run(loadResult);
    final fps = findings.map((f) => f.fingerprint).toList();
    expect(
      fps.length,
      equals(fps.toSet().length),
      reason: 'Each cluster must produce exactly one Finding',
    );
  });

  // ---------------------------------------------------------------------------
  // AC: Message carries all locations
  // ---------------------------------------------------------------------------

  test('message contains occurrence count and all locations', () {
    final findings = makeRule().run(loadResult);
    expect(findings, isNotEmpty);
    for (final f in findings) {
      // message starts with "<n> occurrences of duplicated block"
      expect(f.message, contains('occurrences of duplicated block'));
      // message contains the anchor file path
      expect(f.message, contains(f.filePath));
    }
  });

  test('cross-file cluster message contains both alpha.dart and beta.dart', () {
    final findings = makeRule().run(loadResult);
    final crossFile = findings.where(
      (f) =>
          f.message.contains('lib/alpha.dart') &&
          f.message.contains('lib/beta.dart'),
    );
    expect(
      crossFile,
      isNotEmpty,
      reason: 'Expected at least one finding referencing both fixture files',
    );
  });

  // ---------------------------------------------------------------------------
  // AC: Remedy is present
  // ---------------------------------------------------------------------------

  test('every finding has a non-empty remedy', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.remedy, isNotNull);
      expect(f.remedy!.isNotEmpty, isTrue);
    }
  });

  test('remedy mentions extracting shared function or method', () {
    final findings = makeRule().run(loadResult);
    expect(findings, isNotEmpty);
    for (final f in findings) {
      // remedy must hint at consolidation
      expect(
        f.remedy!.toLowerCase(),
        anyOf(
          contains('extract'),
          contains('shared'),
          contains('function'),
          contains('method'),
        ),
        reason: 'Remedy must hint at consolidation',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // AC: Location is lexicographically first occurrence
  // ---------------------------------------------------------------------------

  test('filePath is the lexicographically first occurrence', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      // Extract all path:line pairs from the message.
      final rest = f.message.split(RegExp(r'\d+ tokens\): ')).last;
      final pairs = rest.split(', ');
      final paths = pairs.map((pair) => pair.split(':').first).toList();
      final sorted = List<String>.from(paths)..sort();
      expect(
        f.filePath,
        equals(sorted.first),
        reason: 'filePath must be the lexicographically smallest path',
      );
    }
  });

  test('line matches the startLine of the anchor occurrence', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.line, greaterThan(0));
      // The anchor path:line must be present in the message.
      expect(
        f.message,
        contains('${f.filePath}:${f.line}'),
        reason: 'Anchor path:line must appear in the message',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // AC: Fingerprint determinism and stability
  // ---------------------------------------------------------------------------

  test('fingerprints are stable across two runs (Invariant 5)', () {
    final run1 = makeRule().run(loadResult);
    final run2 = makeRule().run(loadResult);
    expect(run1.length, equals(run2.length));
    for (var i = 0; i < run1.length; i++) {
      expect(run1[i].fingerprint, equals(run2[i].fingerprint));
    }
  });

  test('fingerprints are 16 characters', () {
    final findings = makeRule().run(loadResult);
    expect(findings, isNotEmpty);
    for (final f in findings) {
      expect(f.fingerprint.length, equals(16));
    }
  });

  test('fingerprint matches computeFingerprint specification', () {
    final findings = makeRule().run(loadResult);
    final clusters = const DuplicateCodeCollector().collect(
      loadResult,
      fixturePath,
    );
    expect(findings, isNotEmpty);
    expect(clusters.length, equals(findings.length));

    for (var i = 0; i < findings.length; i++) {
      final cluster = clusters[i];
      final sortedPaths = cluster.locations.map((l) => l.filePath).toList()
        ..sort();
      final expected = computeFingerprint(
        ruleId: 'code-duplicates',
        relativePath: cluster.locations.first.filePath,
        semanticAnchor:
            'tokens=${cluster.tokenCount}\n'
            'sequence=${cluster.sequenceHash}\n'
            '${sortedPaths.join('\n')}',
      );
      expect(findings[i].fingerprint, equals(expected));
    }
  });

  // ---------------------------------------------------------------------------
  // AC: Fingerprints survive pure line shifts (position-robust, Invariant 5)
  // ---------------------------------------------------------------------------

  group('position-robust fingerprint', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('loam-dup-fingerprint-');
      addTearDown(() => tmp.deleteSync(recursive: true));
    });

    /// Copies the fixture into [tmp] and prepends [shiftLines] blank lines to
    /// every `lib/` file whose name is in [shiftFiles] (all files when null).
    Future<List<String>> fingerprintsAfterShift({
      List<String>? shiftFiles,
      int shiftLines = 0,
      Map<String, String> extraFiles = const {},
    }) async {
      final root = Directory(p.join(tmp.path, 'copy'))..createSync();
      File(
        p.join(fixturePath, 'pubspec.yaml'),
      ).copySync(p.join(root.path, 'pubspec.yaml'));
      final lib = Directory(p.join(root.path, 'lib'))..createSync();
      for (final name in ['alpha.dart', 'beta.dart']) {
        final source = File(
          p.join(fixturePath, 'lib', name),
        ).readAsStringSync();
        final shift = shiftFiles == null || shiftFiles.contains(name)
            ? shiftLines
            : 0;
        File(
          p.join(lib.path, name),
        ).writeAsStringSync('${'\n' * shift}$source');
      }
      extraFiles.forEach((name, content) {
        File(p.join(lib.path, name)).writeAsStringSync(content);
      });

      final result = await ProjectLoader().load(root.path);
      final findings = CodeDuplicatesRule(projectRoot: root.path).run(result);
      expect(findings, isNotEmpty, reason: 'Copy must still contain clones');
      return findings.map((f) => f.fingerprint).toList()..sort();
    }

    test('a pure line shift above every copy keeps all fingerprints', () async {
      final original = await fingerprintsAfterShift();
      final shifted = await fingerprintsAfterShift(shiftLines: 3);
      expect(shifted, equals(original));
    });

    test('a pure line shift above one copy keeps all fingerprints', () async {
      final original = await fingerprintsAfterShift();
      final shifted = await fingerprintsAfterShift(
        shiftFiles: const ['beta.dart'],
        shiftLines: 3,
      );
      expect(shifted, equals(original));
    });

    test('adding a copy changes the fingerprint of the cluster', () async {
      final original = await fingerprintsAfterShift();
      final withCopy = await fingerprintsAfterShift(
        extraFiles: {
          'gamma.dart': File(
            p.join(fixturePath, 'lib', 'alpha.dart'),
          ).readAsStringSync(),
        },
      );
      expect(
        withCopy.toSet().intersection(original.toSet()),
        isEmpty,
        reason: 'An extra occurrence must re-key the affected clusters',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC: kind field
  // ---------------------------------------------------------------------------

  test('all findings carry kind = duplicated-block', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.kind, equals('duplicated-block'));
    }
  });

  // ---------------------------------------------------------------------------
  // AC: Generated files excluded
  // ---------------------------------------------------------------------------

  test('generated files do not appear in any finding', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.message, isNot(contains('.g.dart')));
    }
  });

  // ---------------------------------------------------------------------------
  // AC: Robustness
  // ---------------------------------------------------------------------------

  test('rule does not crash when ProjectLoadResult.errors is non-empty', () {
    final resultWithErrors = ProjectLoadResult(
      resolved: loadResult.resolved,
      errors: const [
        LoadFileError(path: '/fake/broken.dart', reason: 'broken'),
      ],
    );
    final findings = makeRule().run(resultWithErrors);
    expect(findings, isA<List<Finding>>());
  });

  test('rule returns empty list for empty ProjectLoadResult', () {
    const emptyResult = ProjectLoadResult(resolved: [], errors: []);
    final findings = makeRule().run(emptyResult);
    expect(findings, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // AC: Registration in AnalysisRunner
  // ---------------------------------------------------------------------------

  test('code-duplicates is in fullRegistryIds', () {
    expect(AnalysisRunner.fullRegistryIds, contains('code-duplicates'));
  });

  test('fullRegistryIds is lexicographically sorted', () {
    final ids = AnalysisRunner.fullRegistryIds;
    for (var i = 0; i < ids.length - 1; i++) {
      expect(
        ids[i].compareTo(ids[i + 1]),
        lessThan(0),
        reason: '${ids[i]} should sort before ${ids[i + 1]}',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // AC: loam.yaml toggle disables the rule
  // ---------------------------------------------------------------------------

  test('rule toggle false produces no code-duplicates findings', () async {
    final config = LoamConfig(
      ruleToggles: {'code-duplicates': false},
      ignoreGlobs: const [],
    );
    final runner = AnalysisRunner(config: config);
    final findings = await runner.run(fixturePath);
    final duplicateFindings = findings
        .where((f) => f.ruleId == 'code-duplicates')
        .toList();
    expect(
      duplicateFindings,
      isEmpty,
      reason:
          'Disabling code-duplicates via toggle must suppress all its findings',
    );
  });

  // ---------------------------------------------------------------------------
  // AC: rulesetVersion changes when code-duplicates is toggled off
  // ---------------------------------------------------------------------------

  test('disabling code-duplicates changes rulesetVersion', () {
    final defaultVersion = AnalysisRunner.rulesetVersion;
    final config = LoamConfig(
      ruleToggles: {'code-duplicates': false},
      ignoreGlobs: const [],
    );
    final configVersion = AnalysisRunner.rulesetVersionForConfig(config);
    expect(configVersion, isNot(equals(defaultVersion)));
  });

  // ---------------------------------------------------------------------------
  // AC: E2E via AnalysisRunner — fixture produces expected Finding count
  // ---------------------------------------------------------------------------

  test('AnalysisRunner produces code-duplicates findings for fixture', () async {
    final runner = AnalysisRunner();
    final findings = await runner.run(fixturePath);
    final duplicateFindings = findings
        .where((f) => f.ruleId == 'code-duplicates')
        .toList();
    // The fixture has at least 2 known duplicate pairs (Type-1 + Type-2).
    expect(
      duplicateFindings.length,
      greaterThanOrEqualTo(2),
      reason:
          'Fixture has 2 known duplicate pairs; AnalysisRunner must surface them',
    );
  });
}
