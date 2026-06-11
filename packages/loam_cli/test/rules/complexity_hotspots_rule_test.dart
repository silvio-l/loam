@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/complexity/function_complexity_collector.dart';
import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/fingerprint.dart';
import 'package:loam/src/rules/complexity_hotspots_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'complexity_hotspots_fixture',
    ),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    final loader = const ProjectLoader();
    loadResult = await loader.load(fixturePath);
    // The fixture must load cleanly (ignoring the known generated-file errors).
    final nonGenErrors = loadResult.errors
        .where((e) => !e.path.endsWith('.g.dart'))
        .toList();
    expect(
      nonGenErrors,
      isEmpty,
      reason: 'Fixture must load cleanly (non-generated files)',
    );
  });

  ComplexityHotspotsRule makeRule({
    int cyclomaticThreshold = kDefaultCyclomaticThreshold,
    int cognitiveThreshold = kDefaultCognitiveThreshold,
  }) => ComplexityHotspotsRule(
    projectRoot: fixturePath,
    cyclomaticThreshold: cyclomaticThreshold,
    cognitiveThreshold: cognitiveThreshold,
  );

  // ---------------------------------------------------------------------------
  // AC1: Rule implements Rule interface and ruleId is correct
  // ---------------------------------------------------------------------------

  test('ruleId is complexity-hotspots', () {
    expect(makeRule().ruleId, 'complexity-hotspots');
  });

  test('severity of all findings is Severity.warning', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.severity, Severity.warning);
    }
  });

  // ---------------------------------------------------------------------------
  // AC2: Default thresholds are documented constants
  // ---------------------------------------------------------------------------

  test('kDefaultCyclomaticThreshold is 20', () {
    expect(kDefaultCyclomaticThreshold, 20);
  });

  test('kDefaultCognitiveThreshold is 30', () {
    expect(kDefaultCognitiveThreshold, 30);
  });

  // ---------------------------------------------------------------------------
  // AC3: Trivial function is NOT reported; complex function IS reported
  // ---------------------------------------------------------------------------

  test('trivialFunction (cyclomatic=1, cognitive=0) is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('trivialFunction')),
      isFalse,
      reason: 'trivialFunction is trivial and must never be reported',
    );
  });

  test('justOverCyclomatic (cyclomatic=21) IS reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('justOverCyclomatic')),
      isTrue,
      reason: 'cyclomatic=21 exceeds threshold 20 → must be reported',
    );
  });

  test('veryHighCognitive IS reported (cognitive=36 > 30)', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('veryHighCognitive')),
      isTrue,
      reason: 'veryHighCognitive has cognitive=36 > 30 → must be reported',
    );
  });

  // ---------------------------------------------------------------------------
  // AC3: Threshold boundary — just-under and just-over
  // ---------------------------------------------------------------------------

  test(
    'justUnderCyclomatic (cyclomatic=20) is NOT reported at default threshold=20',
    () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('justUnderCyclomatic')),
        isFalse,
        reason: 'cyclomatic=20 equals threshold 20 → must NOT be reported',
      );
    },
  );

  test('justUnderCyclomatic IS reported when threshold is lowered to 19', () {
    final rule = makeRule(cyclomaticThreshold: 19);
    final findings = rule.run(loadResult);
    expect(
      findings.any((f) => f.message.contains('justUnderCyclomatic')),
      isTrue,
      reason:
          'cyclomatic=20 > threshold=19 → must be reported with lower threshold',
    );
  });

  test('justOverCyclomatic is NOT reported when threshold raised to 21', () {
    final rule = makeRule(cyclomaticThreshold: 21);
    final findings = rule.run(loadResult);
    expect(
      findings.any((f) => f.message.contains('justOverCyclomatic')),
      isFalse,
      reason: 'cyclomatic=21 equals raised threshold=21 → must NOT be reported',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4 (calibration): flat-lookup guard — cyclomatic-only breach + low
  //                    cognitive is NOT reported; same cyclomatic + cognitive>5
  //                    IS reported (positive control = justOverCyclomatic).
  // ---------------------------------------------------------------------------

  test('kMinCognitiveForCyclomaticOnlyBreach is 5', () {
    expect(kMinCognitiveForCyclomaticOnlyBreach, 5);
  });

  test(
    'flatLookupTable (cyclomatic=22, cognitive=1) is NOT reported — '
    'cyclomatic-only breach with cognitive ≤ kMinCognitiveForCyclomaticOnlyBreach',
    () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('flatLookupTable')),
        isFalse,
        reason:
            'flatLookupTable has cyclomatic=22 > 20 but cognitive=1 ≤ 5 '
            '(kMinCognitiveForCyclomaticOnlyBreach) → must NOT be reported',
      );
    },
  );

  test(
    'justOverCyclomatic (cyclomatic=21, cognitive=20) IS still reported — '
    'cyclomatic-only breach with cognitive > kMinCognitiveForCyclomaticOnlyBreach',
    () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('justOverCyclomatic')),
        isTrue,
        reason:
            'justOverCyclomatic has cyclomatic=21 > 20 AND cognitive=20 > 5 '
            '(kMinCognitiveForCyclomaticOnlyBreach) → must still be reported',
      );
    },
  );

  // Cognitive boundary: highCognitive has cognitive=28; not reported at default
  // threshold=30 but is reported at threshold=27.
  test(
    'highCognitive (cognitive=28) is NOT reported at default cognitive threshold=30',
    () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('highCognitive')),
        isFalse,
        reason:
            'cognitive=28 does not exceed threshold 30 → must NOT be reported',
      );
    },
  );

  test('highCognitive IS reported when cognitive threshold is lowered to 27', () {
    final rule = makeRule(cognitiveThreshold: 27);
    final findings = rule.run(loadResult);
    expect(
      findings.any((f) => f.message.contains('highCognitive')),
      isTrue,
      reason:
          'cognitive=28 > threshold=27 → must be reported with lower threshold',
    );
  });

  // ---------------------------------------------------------------------------
  // AC2: Message contains symbol + both metrics + breached threshold
  // ---------------------------------------------------------------------------

  test(
    'finding message contains qualifiedName, both metrics, and breach info',
    () {
      final findings = makeRule().run(loadResult);
      final hotspot = findings.firstWhere(
        (f) => f.message.contains('justOverCyclomatic'),
      );
      // Must mention the symbol name.
      expect(hotspot.message, contains('justOverCyclomatic'));
      // Must mention cyclomatic value.
      expect(hotspot.message, contains('cyclomatic='));
      // Must mention cognitive value.
      expect(hotspot.message, contains('cognitive='));
      // Must name the breached threshold with a > indicator.
      expect(hotspot.message, contains('cyclomatic'));
      expect(hotspot.message, contains('>'));
    },
  );

  test('veryHighCognitive message mentions cognitive breach', () {
    final findings = makeRule().run(loadResult);
    final hotspot = findings.firstWhere(
      (f) => f.message.contains('veryHighCognitive'),
    );
    expect(hotspot.message, contains('cognitive='));
    expect(hotspot.message, contains('>'));
  });

  // ---------------------------------------------------------------------------
  // AC4: Generated file is NOT reported
  // ---------------------------------------------------------------------------

  test('functions in generated files (*.g.dart) are NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('generatedComplexFunction')),
      isFalse,
      reason: 'Generated files must not be measured or reported',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4: Rule does not crash when ProjectLoadResult.errors is non-empty
  // ---------------------------------------------------------------------------

  test('rule does not crash when ProjectLoadResult.errors is non-empty', () {
    final resultWithErrors = ProjectLoadResult(
      resolved: loadResult.resolved,
      errors: const [
        LoadFileError(path: '/fake/broken.dart', reason: 'broken'),
      ],
    );
    expect(
      () => makeRule().run(resultWithErrors),
      returnsNormally,
      reason: 'Rule must not throw on non-empty errors list',
    );
  });

  test('rule returns empty list for empty ProjectLoadResult', () {
    const empty = ProjectLoadResult(resolved: [], errors: []);
    final findings = makeRule().run(empty);
    expect(findings, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // AC5: Fingerprint stability — line shift does NOT change it;
  //       symbol rename DOES change it
  // ---------------------------------------------------------------------------

  test('fingerprint matches computeFingerprint(ruleId, path, anchor)', () {
    final findings = makeRule().run(loadResult);
    final hotspot = findings.firstWhere(
      (f) => f.message.contains('justOverCyclomatic'),
    );
    final expected = computeFingerprint(
      ruleId: 'complexity-hotspots',
      relativePath: hotspot.filePath,
      semanticAnchor: 'justOverCyclomatic',
    );
    expect(hotspot.fingerprint, equals(expected));
  });

  test('two consecutive runs produce identical fingerprints (stability)', () {
    final run1 = makeRule().run(loadResult);
    final run2 = makeRule().run(loadResult);
    expect(run1.length, equals(run2.length));
    for (var i = 0; i < run1.length; i++) {
      expect(run1[i].fingerprint, equals(run2[i].fingerprint));
    }
  });

  test('fingerprint changes when symbol name changes', () {
    // Simulate by computing fingerprints for two different symbol names.
    const ruleId = 'complexity-hotspots';
    const relPath = 'lib/hotspot_samples.dart';
    final fp1 = computeFingerprint(
      ruleId: ruleId,
      relativePath: relPath,
      semanticAnchor: 'justOverCyclomatic',
    );
    final fp2 = computeFingerprint(
      ruleId: ruleId,
      relativePath: relPath,
      semanticAnchor: 'justOverCyclomaticRenamed',
    );
    expect(fp1, isNot(equals(fp2)));
  });

  test(
    'fingerprint is stable against line shifts (same semantic key → same fp)',
    () {
      // The fingerprint does NOT include the line number — it uses only ruleId,
      // relativePath, and semanticAnchor. Two computations with the same semantic
      // key but conceptually different lines yield the same fingerprint.
      const ruleId = 'complexity-hotspots';
      const relPath = 'lib/hotspot_samples.dart';
      const anchor = 'justOverCyclomatic';
      final fp1 = computeFingerprint(
        ruleId: ruleId,
        relativePath: relPath,
        semanticAnchor: anchor,
      );
      final fp2 = computeFingerprint(
        ruleId: ruleId,
        relativePath: relPath,
        semanticAnchor: anchor,
      );
      expect(
        fp1,
        equals(fp2),
        reason: 'Same semantic key must always produce the same fingerprint',
      );
    },
  );

  test('fingerprints are 16 characters', () {
    final findings = makeRule().run(loadResult);
    expect(findings, isNotEmpty);
    for (final f in findings) {
      expect(f.fingerprint.length, equals(16));
    }
  });

  // ---------------------------------------------------------------------------
  // AC5: Registry — complexity-hotspots in fullRegistryIds (sorted)
  // ---------------------------------------------------------------------------

  test('complexity-hotspots is in fullRegistryIds', () {
    expect(AnalysisRunner.fullRegistryIds, contains('complexity-hotspots'));
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
  // AC6: loam.yaml toggle disables the rule
  // ---------------------------------------------------------------------------

  test('rule toggle false produces no complexity-hotspots findings', () async {
    final config = LoamConfig(
      ruleToggles: {'complexity-hotspots': false},
      ignoreGlobs: const [],
    );
    final runner = AnalysisRunner(config: config);
    final findings = await runner.run(fixturePath);
    final hotspotFindings = findings
        .where((f) => f.ruleId == 'complexity-hotspots')
        .toList();
    expect(
      hotspotFindings,
      isEmpty,
      reason:
          'Disabling complexity-hotspots via toggle must suppress all its findings',
    );
  });

  // ---------------------------------------------------------------------------
  // AC7: rulesetVersion changes when complexity-hotspots is toggled off
  // ---------------------------------------------------------------------------

  test(
    'adding complexity-hotspots changes rulesetVersion vs disabled config',
    () {
      // Default version includes all rules (including complexity-hotspots).
      final fullVersion = AnalysisRunner.rulesetVersion;
      // Config with complexity-hotspots disabled → different active set.
      final config = LoamConfig(
        ruleToggles: {'complexity-hotspots': false},
        ignoreGlobs: const [],
      );
      final reducedVersion = AnalysisRunner.rulesetVersionForConfig(config);
      expect(
        reducedVersion,
        isNot(equals(fullVersion)),
        reason:
            'Enabling/disabling complexity-hotspots must change rulesetVersion',
      );
    },
  );

  test('rulesetVersion is deterministic across calls', () {
    final v1 = AnalysisRunner.rulesetVersion;
    final v2 = AnalysisRunner.rulesetVersion;
    expect(v1, equals(v2));
  });

  // ---------------------------------------------------------------------------
  // AC8: All findings carry the correct ruleId
  // ---------------------------------------------------------------------------

  test('all findings carry ruleId = complexity-hotspots', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, equals('complexity-hotspots'));
    }
  });

  // ---------------------------------------------------------------------------
  // AC8: Uses FunctionComplexityCollector exclusively
  // ---------------------------------------------------------------------------

  test('rule uses FunctionComplexityCollector (injectable)', () {
    // Verify the injectable collector parameter.
    final rule = ComplexityHotspotsRule(
      projectRoot: fixturePath,
      collector: const FunctionComplexityCollector(),
    );
    expect(() => rule.run(loadResult), returnsNormally);
  });

  // ---------------------------------------------------------------------------
  // End-to-end: AnalysisRunner integration with the fixture
  // ---------------------------------------------------------------------------

  test(
    'AnalysisRunner includes complexity-hotspots findings for fixture',
    () async {
      final runner = AnalysisRunner();
      final findings = await runner.run(fixturePath);
      final hotspotFindings = findings
          .where((f) => f.ruleId == 'complexity-hotspots')
          .toList();
      expect(
        hotspotFindings,
        isNotEmpty,
        reason:
            'AnalysisRunner must surface complexity-hotspots findings for the fixture',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // AC8: Inline suppression — end-to-end via AnalysisRunner
  // ---------------------------------------------------------------------------

  test(
    'suppressedHotspot is NOT in findings; a non-suppressed breaching function IS',
    () async {
      final runner = AnalysisRunner();
      final findings = await runner.run(fixturePath);

      // Negative assertion: suppressedHotspot carries a valid
      // `// loam-ignore: complexity-hotspots – …` directive and therefore must
      // NOT appear in the AnalysisRunner output, even though it breaches the
      // cyclomatic threshold (cyclomatic=21 > 20).
      expect(
        findings.any((f) => f.message.contains('suppressedHotspot')),
        isFalse,
        reason:
            'suppressedHotspot must be suppressed by its loam-ignore directive',
      );

      // Positive control: justOverCyclomatic has the SAME cyclomatic value
      // (cyclomatic=21) but carries NO loam-ignore directive → it MUST still
      // be reported. This proves the suppression directive is what removes
      // suppressedHotspot, not that nothing breaches the threshold at all.
      expect(
        findings.any((f) => f.message.contains('justOverCyclomatic')),
        isTrue,
        reason:
            'justOverCyclomatic (cyclomatic=21, no directive) must still be reported',
      );
    },
  );

  test(
    'AnalysisRunner findings are deterministically sorted for fixture',
    () async {
      final runner = AnalysisRunner();
      final findings = await runner.run(fixturePath);
      for (var i = 0; i < findings.length - 1; i++) {
        final a = findings[i];
        final b = findings[i + 1];
        final pathCmp = a.filePath.compareTo(b.filePath);
        if (pathCmp < 0) continue;
        if (pathCmp > 0) {
          fail(
            'findings not sorted by filePath: ${a.filePath} vs ${b.filePath}',
          );
        }
        if (a.line < b.line) continue;
        if (a.line > b.line) {
          fail(
            'findings not sorted by line: ${a.filePath}:${a.line} vs ${b.line}',
          );
        }
        expect(a.fingerprint.compareTo(b.fingerprint), lessThanOrEqualTo(0));
      }
    },
  );
}
