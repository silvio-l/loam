@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/report/human_reporter.dart';
import 'package:loam/src/report/json_reporter.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/sarif_reporter.dart';
import 'package:loam/src/rules/a11y_image_label_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'a11y_image_label_fixture',
    ),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    // Ensure the flutter_stub path dependency is resolved: the .dart_tool/
    // package_config.json is gitignored and must be regenerated after a fresh
    // clone. Running 'dart pub get' is idempotent and quick when already done.
    final pubGetResult = await Process.run('dart', [
      'pub',
      'get',
    ], workingDirectory: fixturePath);
    if (pubGetResult.exitCode != 0) {
      fail(
        'dart pub get failed in fixture:\n'
        '${pubGetResult.stdout}\n${pubGetResult.stderr}',
      );
    }

    final loader = const ProjectLoader();
    loadResult = await loader.load(fixturePath);

    // The fixture must load cleanly. Only generated files may produce errors
    // (the `.g.dart` file in the fixture intentionally imports flutter/widgets
    // but the resolver might surface minor diagnostic differences).
    final nonGenErrors = loadResult.errors
        .where((e) => !e.path.endsWith('.g.dart'))
        .toList();
    expect(
      nonGenErrors,
      isEmpty,
      reason:
          'Fixture must load cleanly (non-generated files). '
          'Errors: ${loadResult.errors.map((e) => "${e.path}: ${e.reason}").join("; ")}',
    );
  });

  A11yImageLabelRule makeRule() => A11yImageLabelRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // Interface contract
  // ---------------------------------------------------------------------------

  test('ruleId is a11y-image-label', () {
    expect(makeRule().ruleId, 'a11y-image-label');
  });

  test('static ruleIdStatic matches ruleId', () {
    expect(A11yImageLabelRule.ruleIdStatic, makeRule().ruleId);
  });

  test('category is RuleCategory.accessibility', () {
    expect(makeRule().category, RuleCategory.accessibility);
  });

  // ---------------------------------------------------------------------------
  // AC1: Positive fixture — unlabelled Images produce findings
  // ---------------------------------------------------------------------------

  test(
    'AC1: 5 findings for unlabelled Image calls in image_missing_label.dart',
    () {
      final findings = makeRule().run(loadResult);
      // There are 5 Image instantiations without semanticLabel/excludeFromSemantics:
      //   Image.asset(), Image.network(), Image.file(), Image.memory(), Image()
      expect(
        findings,
        hasLength(5),
        reason:
            'Expected exactly 5 findings (one per unlabelled Image call). '
            'Got: ${findings.map((f) => f.message).join(", ")}',
      );
    },
  );

  test('AC1: all findings have ruleId a11y-image-label', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, 'a11y-image-label');
    }
  });

  test('AC1: all findings have Severity.warning', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.severity, Severity.warning);
    }
  });

  test('AC1: findings cover all 5 constructor variants', () {
    final findings = makeRule().run(loadResult);
    final messages = findings.map((f) => f.message).toList();
    expect(
      messages.any((m) => m.contains('.asset()')),
      isTrue,
      reason: 'Image.asset() should produce a finding',
    );
    expect(
      messages.any((m) => m.contains('.network()')),
      isTrue,
      reason: 'Image.network() should produce a finding',
    );
    expect(
      messages.any((m) => m.contains('.file()')),
      isTrue,
      reason: 'Image.file() should produce a finding',
    );
    expect(
      messages.any((m) => m.contains('.memory()')),
      isTrue,
      reason: 'Image.memory() should produce a finding',
    );
    expect(
      messages.any((m) => m.contains('Image()')),
      isTrue,
      reason: 'unnamed Image() should produce a finding',
    );
  });

  // ---------------------------------------------------------------------------
  // AC2: Negative fixture — labelled or excluded Images produce no findings
  // ---------------------------------------------------------------------------

  test(
    'AC2: no findings for Image with semanticLabel (including empty string)',
    () {
      final findings = makeRule().run(loadResult);
      // image_with_label.dart contains: Image.asset(semanticLabel: 'Company logo'),
      // Image.asset(semanticLabel: ''), Image.network(semanticLabel: 'Hero banner')
      // None should be reported.
      final labeled = findings.where(
        (f) => f.filePath.contains('image_with_label'),
      );
      expect(
        labeled,
        isEmpty,
        reason: 'Images with semanticLabel must not be flagged',
      );
    },
  );

  test('AC2: no findings for Image with excludeFromSemantics: true', () {
    final findings = makeRule().run(loadResult);
    final excluded = findings.where(
      (f) => f.filePath.contains('image_excluded'),
    );
    expect(
      excluded,
      isEmpty,
      reason: 'Images with excludeFromSemantics: true must not be flagged',
    );
  });

  // ---------------------------------------------------------------------------
  // AC3: Non-Flutter Image and generated files must be ignored
  // ---------------------------------------------------------------------------

  test(
    'AC3: local MyImage class (not package:flutter) produces no findings',
    () {
      final findings = makeRule().run(loadResult);
      final alias = findings.where((f) => f.filePath.contains('image_alias'));
      expect(
        alias,
        isEmpty,
        reason: 'MyImage is not Flutter Image — must not be flagged',
      );
    },
  );

  test('AC3: generated file (*.g.dart) produces no findings', () {
    final findings = makeRule().run(loadResult);
    final generated = findings.where((f) => f.filePath.endsWith('.g.dart'));
    expect(generated, isEmpty, reason: 'Generated files must be skipped');
  });

  // ---------------------------------------------------------------------------
  // AC4: Determinism — two runs produce identical fingerprints
  // ---------------------------------------------------------------------------

  test('AC4: fingerprints are identical across two independent runs', () {
    final run1 = makeRule().run(loadResult);
    final run2 = makeRule().run(loadResult);

    expect(run1.length, run2.length);
    for (var i = 0; i < run1.length; i++) {
      expect(
        run1[i].fingerprint,
        run2[i].fingerprint,
        reason: 'Fingerprint mismatch at index $i',
      );
    }
  });

  test('AC4: each finding fingerprint has exactly 16 characters', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.fingerprint.length, 16, reason: 'Fingerprint: ${f.fingerprint}');
    }
  });

  test('AC4: all fingerprints are distinct', () {
    final findings = makeRule().run(loadResult);
    final fingerprints = findings.map((f) => f.fingerprint).toSet();
    expect(
      fingerprints.length,
      findings.length,
      reason: 'All findings must have distinct fingerprints',
    );
  });

  // ---------------------------------------------------------------------------
  // AC5: Reporter pass-through — wcagRef is emitted by all reporters
  // ---------------------------------------------------------------------------

  group('AC5: reporter pass-through', () {
    late Finding sampleFinding;

    setUp(() {
      // Construct a sample finding with wcagRef manually for reporter tests.
      sampleFinding = makeRule().run(loadResult).first;
    });

    test('AC5: finding has non-null wcagRef', () {
      expect(sampleFinding.wcagRef, isNotNull);
    });

    test('AC5: wcagRef carries WCAG 1.1.1 data', () {
      final ref = sampleFinding.wcagRef!;
      expect(ref.number, '1.1.1');
      expect(ref.title, 'Non-text Content');
      expect(ref.url, contains('WCAG'));
    });

    test('AC5: JsonReporter emits wcagRef block', () {
      final payload = ReportPayload(
        findings: [sampleFinding],
        suppressedCount: 0,
        toolVersion: '0.0.0-test',
        rulesetVersion: 'ruleset@test',
        projectRoot: fixturePath,
        isTty: false,
      );
      final json = const JsonReporter().render(payload);
      expect(json, contains('"wcagRef"'));
      expect(json, contains('"number"'));
      expect(json, contains('"1.1.1"'));
      expect(json, contains('"Non-text Content"'));
    });

    test('AC5: SarifReporter emits wcagRef in properties bag', () {
      final payload = ReportPayload(
        findings: [sampleFinding],
        suppressedCount: 0,
        toolVersion: '0.0.0-test',
        rulesetVersion: 'ruleset@test',
        projectRoot: fixturePath,
        isTty: false,
      );
      final sarif = const SarifReporter().render(payload);
      expect(sarif, contains('wcagRef'));
      expect(sarif, contains('1.1.1'));
    });

    test('AC5: HumanReporter emits WCAG note line', () {
      final payload = ReportPayload(
        findings: [sampleFinding],
        suppressedCount: 0,
        toolVersion: '0.0.0-test',
        rulesetVersion: 'ruleset@test',
        projectRoot: fixturePath,
        isTty: false,
      );
      final human = const HumanReporter().render(payload);
      expect(human, contains('WCAG 1.1.1'));
      expect(human, contains('Non-text Content'));
    });
  });

  // ---------------------------------------------------------------------------
  // AC6: Contract — kind and remedy are non-empty
  // ---------------------------------------------------------------------------

  test('AC6: kind is "missing-semantic-label"', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.kind, 'missing-semantic-label');
    }
  });

  test('AC6: remedy is non-empty and actionable', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.remedy, isNotNull);
      expect(f.remedy, isNotEmpty);
    }
  });

  // ---------------------------------------------------------------------------
  // AC7: AnalysisRunner — rule participates in category-filtered a11y run
  // ---------------------------------------------------------------------------

  test('AC7: a11y-image-label is in fullRegistryIds', () {
    expect(AnalysisRunner.fullRegistryIds, contains('a11y-image-label'));
  });

  test('AC7: a11y-image-label belongs to RuleCategory.accessibility', () {
    final a11yIds = AnalysisRunner.activeIdsForCategory(
      RuleCategory.accessibility,
    );
    expect(a11yIds, contains('a11y-image-label'));
  });

  test(
    'AC7: AnalysisRunner with includeA11y:true includes a11y-image-label',
    () {
      // LoamConfig.defaults() has includeA11y: true — a11y rules are included.
      const config = LoamConfig.defaults();
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, contains('a11y-image-label'));
    },
  );

  test(
    'AC7: AnalysisRunner with includeA11y:false excludes a11y-image-label',
    () {
      const config = LoamConfig(
        ruleToggles: {},
        ignoreGlobs: [],
        includeA11y: false,
      );
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, isNot(contains('a11y-image-label')));
    },
  );
}
