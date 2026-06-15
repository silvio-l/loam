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
import 'package:loam/src/rules/a11y_form_field_label_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'a11y_form_field_label_fixture',
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

    // The fixture must load cleanly. Only generated files may produce errors.
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

  A11yFormFieldLabelRule makeRule() =>
      A11yFormFieldLabelRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // Interface contract
  // ---------------------------------------------------------------------------

  test('ruleId is a11y-form-field-label', () {
    expect(makeRule().ruleId, 'a11y-form-field-label');
  });

  test('static ruleIdStatic matches ruleId', () {
    expect(A11yFormFieldLabelRule.ruleIdStatic, makeRule().ruleId);
  });

  test('category is RuleCategory.accessibility', () {
    expect(makeRule().category, RuleCategory.accessibility);
  });

  // ---------------------------------------------------------------------------
  // AC1: Positive — TextField without label → findings
  // ---------------------------------------------------------------------------

  test('AC1: bare TextField() without decoration → one finding', () {
    final findings = makeRule().run(loadResult);
    final bareFindings = findings
        .where(
          (f) =>
              f.filePath.contains('text_field_missing_label') &&
              !f.filePath.endsWith('.g.dart'),
        )
        .toList();
    expect(
      bareFindings,
      hasLength(2),
      reason:
          'Expected 2 findings in text_field_missing_label.dart '
          '(bare TextField + InputDecoration with no labelText/hintText). '
          'Got: ${bareFindings.map((f) => f.message).join(", ")}',
    );
  });

  test('AC1: finding ruleId is a11y-form-field-label', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, 'a11y-form-field-label');
    }
  });

  test('AC1: finding severity is Severity.warning', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.severity, Severity.warning);
    }
  });

  test('AC1: finding kind is "missing-form-label"', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.kind, 'missing-form-label');
    }
  });

  test('AC1: finding message mentions TextField or TextFormField', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      final mentionsWidget =
          f.message.contains('TextField') ||
          f.message.contains('TextFormField');
      expect(
        mentionsWidget,
        isTrue,
        reason: 'Message should mention the widget type: ${f.message}',
      );
    }
  });

  test(
    'AC1: TextField(decoration: InputDecoration()) without label → finding',
    () {
      final findings = makeRule().run(loadResult);
      final decorNoLabelFindings = findings.where(
        (f) =>
            f.filePath.contains('text_field_missing_label') &&
            !f.filePath.endsWith('.g.dart'),
      );
      // Both buildBareTextField and buildDecorationNoLabel should be flagged.
      expect(
        decorNoLabelFindings.length,
        2,
        reason:
            'Both bare TextField and InputDecoration-without-label should flag',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // AC2: Negative — labelText / hintText / Semantics wrapper → no finding
  // ---------------------------------------------------------------------------

  test('AC2: no findings in text_field_clean.dart', () {
    final findings = makeRule().run(loadResult);
    final cleanFindings = findings.where(
      (f) => f.filePath.contains('text_field_clean'),
    );
    expect(
      cleanFindings,
      isEmpty,
      reason:
          'text_field_clean.dart contains only clean widgets '
          '(labelText, hintText, Semantics wrapper) — zero findings expected',
    );
  });

  test(
    'AC2: TextField(decoration: InputDecoration(labelText:)) → no finding',
    () {
      final findings = makeRule().run(loadResult);
      final labelFindings = findings.where(
        (f) =>
            f.filePath.contains('text_field_clean') &&
            f.message.contains('labelText'),
      );
      expect(labelFindings, isEmpty);
    },
  );

  test('AC2: Semantics(label:) ancestor → no finding', () {
    final findings = makeRule().run(loadResult);
    final semanticsFindings = findings.where(
      (f) => f.filePath.contains('text_field_clean'),
    );
    expect(
      semanticsFindings,
      isEmpty,
      reason: 'Semantics-wrapped TextField must not be flagged',
    );
  });

  // ---------------------------------------------------------------------------
  // AC3: TextFormField — positive and negative
  // ---------------------------------------------------------------------------

  test('AC3: bare TextFormField() → one finding', () {
    final findings = makeRule().run(loadResult);
    final formFindings = findings
        .where((f) => f.filePath.contains('text_form_field_cases'))
        .toList();
    expect(
      formFindings,
      hasLength(1),
      reason:
          'Expected exactly 1 finding in text_form_field_cases.dart '
          '(bare TextFormField). '
          'Got: ${formFindings.map((f) => f.message).join(", ")}',
    );
  });

  test('AC3: TextFormField positive finding mentions TextFormField', () {
    final findings = makeRule().run(loadResult);
    final formFinding = findings.firstWhere(
      (f) => f.filePath.contains('text_form_field_cases'),
    );
    expect(formFinding.message, contains('TextFormField'));
  });

  test(
    'AC3: TextFormField(decoration: InputDecoration(labelText:)) → no finding',
    () {
      final findings = makeRule().run(loadResult);
      final formFindings = findings.where(
        (f) => f.filePath.contains('text_form_field_cases'),
      );
      // Only 1 finding (the bare one), not 2. The labelled one must be clean.
      expect(formFindings, hasLength(1));
    },
  );

  // ---------------------------------------------------------------------------
  // AC4: Alias/codegen counter-examples → no finding
  // ---------------------------------------------------------------------------

  test('AC4: local TextField class (not package:flutter) → no finding', () {
    final findings = makeRule().run(loadResult);
    final aliasFindings = findings.where(
      (f) => f.filePath.contains('text_field_alias'),
    );
    expect(
      aliasFindings,
      isEmpty,
      reason: 'Local TextField is not Flutter TextField — must not be flagged',
    );
  });

  test('AC4: generated file (*.g.dart) → no finding', () {
    final findings = makeRule().run(loadResult);
    final generatedFindings = findings.where(
      (f) => f.filePath.endsWith('.g.dart'),
    );
    expect(
      generatedFindings,
      isEmpty,
      reason: 'Generated files must be skipped',
    );
  });

  // ---------------------------------------------------------------------------
  // Total finding count sanity check
  // ---------------------------------------------------------------------------

  test(
    'total findings: 2 (text_field_missing_label) + 1 (text_form_field) = 3',
    () {
      final findings = makeRule().run(loadResult);
      expect(
        findings,
        hasLength(3),
        reason:
            'Expected exactly 3 findings total. '
            'Got: ${findings.map((f) => "${f.filePath}:${f.line} ${f.message}").join("; ")}',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // AC5: Determinism + fingerprint + WCAG ref in all reporters
  // ---------------------------------------------------------------------------

  test('AC5: fingerprints are identical across two independent runs', () {
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

  test('AC5: each finding fingerprint has exactly 16 characters', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.fingerprint.length, 16, reason: 'Fingerprint: ${f.fingerprint}');
    }
  });

  test('AC5: all fingerprints are distinct', () {
    final findings = makeRule().run(loadResult);
    final fingerprints = findings.map((f) => f.fingerprint).toSet();
    expect(
      fingerprints.length,
      findings.length,
      reason: 'All findings must have distinct fingerprints',
    );
  });

  group('AC5: reporter pass-through', () {
    late Finding sampleFinding;

    setUp(() {
      sampleFinding = makeRule().run(loadResult).first;
    });

    test('AC5: finding has non-null wcagRef', () {
      expect(sampleFinding.wcagRef, isNotNull);
    });

    test('AC5: wcagRef carries WCAG 3.3.2 data', () {
      final ref = sampleFinding.wcagRef!;
      expect(ref.number, '3.3.2');
      expect(ref.title, 'Labels or Instructions');
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
      expect(json, contains('"3.3.2"'));
      expect(json, contains('"Labels or Instructions"'));
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
      expect(sarif, contains('3.3.2'));
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
      expect(human, contains('WCAG 3.3.2'));
      expect(human, contains('Labels or Instructions'));
    });
  });

  // ---------------------------------------------------------------------------
  // AC5: remedy is non-empty and actionable
  // ---------------------------------------------------------------------------

  test('AC5: remedy is non-empty and actionable', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.remedy, isNotNull);
      expect(f.remedy, isNotEmpty);
      expect(f.remedy, contains('InputDecoration'));
    }
  });

  // ---------------------------------------------------------------------------
  // AC6: AnalysisRunner — rule participates in registry and category filter
  // ---------------------------------------------------------------------------

  test('AC6: a11y-form-field-label is in fullRegistryIds', () {
    expect(AnalysisRunner.fullRegistryIds, contains('a11y-form-field-label'));
  });

  test('AC6: a11y-form-field-label belongs to RuleCategory.accessibility', () {
    final a11yIds = AnalysisRunner.activeIdsForCategory(
      RuleCategory.accessibility,
    );
    expect(a11yIds, contains('a11y-form-field-label'));
  });

  test(
    'AC6: AnalysisRunner with includeA11y:true includes a11y-form-field-label',
    () {
      const config = LoamConfig.defaults();
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, contains('a11y-form-field-label'));
    },
  );

  test(
    'AC6: AnalysisRunner with includeA11y:false excludes a11y-form-field-label',
    () {
      const config = LoamConfig(
        ruleToggles: {},
        ignoreGlobs: [],
        includeA11y: false,
      );
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, isNot(contains('a11y-form-field-label')));
    },
  );

  test('AC6: fullRegistryIds is sorted lexicographically '
      '(a11y-form-field-label before a11y-icon-button-label)', () {
    final ids = AnalysisRunner.fullRegistryIds;
    final formIdx = ids.indexOf('a11y-form-field-label');
    final iconIdx = ids.indexOf('a11y-icon-button-label');
    expect(formIdx, lessThan(iconIdx));
  });
}
