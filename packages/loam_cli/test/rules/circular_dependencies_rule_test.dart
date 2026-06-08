@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/fingerprint.dart';
import 'package:loam/src/rules/circular_dependencies_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'circular_deps_fixture'),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    final loader = ProjectLoader();
    loadResult = await loader.load(fixturePath);
    expect(loadResult.errors, isEmpty, reason: 'Fixture must load cleanly');
  });

  CircularDependenciesRule makeRule() =>
      CircularDependenciesRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // AC1: Rule implements Rule interface and ruleId is correct
  // ---------------------------------------------------------------------------
  test('ruleId is circular-dependencies', () {
    expect(makeRule().ruleId, 'circular-dependencies');
  });

  test('severity of all findings is Severity.warning', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.severity, Severity.warning);
    }
  });

  // ---------------------------------------------------------------------------
  // AC2: Import cycle (alpha ↔ beta) produces exactly one Finding
  // ---------------------------------------------------------------------------
  test('import cycle alpha↔beta produces exactly one finding', () {
    final findings = makeRule().run(loadResult);
    final cycleFinding = findings.where(
      (f) =>
          f.message.contains('lib/alpha.dart') &&
          f.message.contains('lib/beta.dart'),
    );
    expect(
      cycleFinding,
      hasLength(1),
      reason: 'Exactly one finding for the alpha↔beta import cycle',
    );
  });

  // ---------------------------------------------------------------------------
  // AC3: Export cycle (zeta ↔ eta) produces exactly one Finding
  // ---------------------------------------------------------------------------
  test('export cycle zeta↔eta produces exactly one finding', () {
    final findings = makeRule().run(loadResult);
    final cycleFinding = findings.where(
      (f) =>
          f.message.contains('lib/eta.dart') &&
          f.message.contains('lib/zeta.dart'),
    );
    expect(
      cycleFinding,
      hasLength(1),
      reason: 'Exactly one finding for the eta↔zeta export cycle',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4: Acyclic control set (delta, gamma, epsilon, external_user,
  //       relative_importer, codegen_host) produces NO findings
  // ---------------------------------------------------------------------------
  test('acyclic files do not appear as cycle members', () {
    final findings = makeRule().run(loadResult);
    final acyclic = [
      'lib/delta.dart',
      'lib/gamma.dart',
      'lib/epsilon.dart',
      'lib/external_user.dart',
      'lib/relative_importer.dart',
      'lib/codegen_host.dart',
    ];
    for (final file in acyclic) {
      expect(
        findings.any((f) => f.message.contains(file)),
        isFalse,
        reason: '$file is acyclic and must not appear in any finding message',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // AC5: Generated file (codegen_host.g.dart) and part file
  //       (src/epsilon_part.dart) do NOT produce findings
  // ---------------------------------------------------------------------------
  test('generated file does not appear in findings', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('codegen_host.g.dart')),
      isFalse,
      reason: 'Generated files must not be nodes in the graph',
    );
  });

  test('part file does not appear in findings', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('epsilon_part.dart')),
      isFalse,
      reason: 'Part files must not be nodes in the graph',
    );
  });

  // ---------------------------------------------------------------------------
  // AC6: Exactly one Finding per SCC cluster (no duplicates)
  // ---------------------------------------------------------------------------
  test('exactly one finding per cluster (no duplicate fingerprints)', () {
    final findings = makeRule().run(loadResult);
    final fingerprints = findings.map((f) => f.fingerprint).toList();
    expect(
      fingerprints.length,
      equals(fingerprints.toSet().length),
      reason: 'No duplicate fingerprints — exactly one Finding per cluster',
    );
  });

  // ---------------------------------------------------------------------------
  // AC7: Finding location is the lexicographically smallest cluster member,
  //       line = 1, no column
  // ---------------------------------------------------------------------------
  test('finding filePath is lexicographically smallest cluster member', () {
    final findings = makeRule().run(loadResult);
    expect(findings, isNotEmpty);
    for (final f in findings) {
      // The smallest member is the one whose path sorts first.
      // Extract listed members from the message.
      final raw = f.message.replaceFirst('circular dependency between: ', '');
      final members = raw.split(', ');
      final smallest = (List<String>.from(members)..sort()).first;
      expect(
        f.filePath,
        equals(smallest),
        reason: 'filePath must be the lexicographically smallest member',
      );
    }
  });

  test('finding line is 1', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.line, equals(1));
    }
  });

  test('finding column is null (file-level, no column)', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.column, isNull);
    }
  });

  // ---------------------------------------------------------------------------
  // AC8: Fingerprint stability — same cluster → same fingerprint across runs
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

  // ---------------------------------------------------------------------------
  // AC9: Fingerprint specification — matches computeFingerprint directly
  // ---------------------------------------------------------------------------
  test('alpha↔beta fingerprint matches specification', () {
    final findings = makeRule().run(loadResult);
    final alphaBeta = findings.firstWhere(
      (f) =>
          f.message.contains('lib/alpha.dart') &&
          f.message.contains('lib/beta.dart'),
    );
    // Cluster members sorted: [lib/alpha.dart, lib/beta.dart]
    final expectedFingerprint = computeFingerprint(
      ruleId: 'circular-dependencies',
      relativePath: 'lib/alpha.dart',
      semanticAnchor: 'lib/alpha.dart\nlib/beta.dart',
    );
    expect(alphaBeta.fingerprint, equals(expectedFingerprint));
  });

  test('eta↔zeta fingerprint matches specification', () {
    final findings = makeRule().run(loadResult);
    final etaZeta = findings.firstWhere(
      (f) =>
          f.message.contains('lib/eta.dart') &&
          f.message.contains('lib/zeta.dart'),
    );
    // Cluster members sorted: [lib/eta.dart, lib/zeta.dart]
    final expectedFingerprint = computeFingerprint(
      ruleId: 'circular-dependencies',
      relativePath: 'lib/eta.dart',
      semanticAnchor: 'lib/eta.dart\nlib/zeta.dart',
    );
    expect(etaZeta.fingerprint, equals(expectedFingerprint));
  });

  // ---------------------------------------------------------------------------
  // AC10: All findings carry the correct ruleId
  // ---------------------------------------------------------------------------
  test('all findings carry ruleId = circular-dependencies', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, equals('circular-dependencies'));
    }
  });

  // ---------------------------------------------------------------------------
  // AC11: Rule does not crash when ProjectLoadResult.errors is non-empty
  // ---------------------------------------------------------------------------
  test('rule does not crash on non-empty errors list', () {
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
  // AC12: Registered in AnalysisRunner.fullRegistryIds (lexicographic order)
  // ---------------------------------------------------------------------------
  test('circular-dependencies is in fullRegistryIds', () {
    expect(AnalysisRunner.fullRegistryIds, contains('circular-dependencies'));
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
  // AC13: loam.yaml toggle disables the rule (no findings, not instantiated)
  // ---------------------------------------------------------------------------
  test('rule toggle false produces no circular-dependencies findings', () async {
    final config = LoamConfig(
      ruleToggles: {'circular-dependencies': false},
      ignoreGlobs: const [],
    );
    final runner = AnalysisRunner(config: config);
    final findings = await runner.run(fixturePath);
    final circularFindings = findings
        .where((f) => f.ruleId == 'circular-dependencies')
        .toList();
    expect(
      circularFindings,
      isEmpty,
      reason:
          'Disabling circular-dependencies via toggle must suppress all its findings',
    );
  });

  // ---------------------------------------------------------------------------
  // AC14: rulesetVersion changes when circular-dependencies is toggled off
  // ---------------------------------------------------------------------------
  test('disabling circular-dependencies changes rulesetVersion', () {
    final defaultVersion = AnalysisRunner.rulesetVersion;
    final config = LoamConfig(
      ruleToggles: {'circular-dependencies': false},
      ignoreGlobs: const [],
    );
    final configVersion = AnalysisRunner.rulesetVersionForConfig(config);
    expect(configVersion, isNot(equals(defaultVersion)));
  });

  // ---------------------------------------------------------------------------
  // AC15: Message contains sorted member filenames
  // ---------------------------------------------------------------------------
  test('message lists cluster members in sorted order', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      final raw = f.message.replaceFirst('circular dependency between: ', '');
      final members = raw.split(', ');
      final sorted = List<String>.from(members)..sort();
      expect(
        members,
        equals(sorted),
        reason: 'Members in message must be in sorted order',
      );
    }
  });
}
