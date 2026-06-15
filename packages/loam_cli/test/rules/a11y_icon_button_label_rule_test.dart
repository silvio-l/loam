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
import 'package:loam/src/rules/a11y_icon_button_label_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'a11y_icon_button_label_fixture',
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

  A11yIconButtonLabelRule makeRule() =>
      A11yIconButtonLabelRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // Interface contract
  // ---------------------------------------------------------------------------

  test('ruleId is a11y-icon-button-label', () {
    expect(makeRule().ruleId, 'a11y-icon-button-label');
  });

  test('static ruleIdStatic matches ruleId', () {
    expect(A11yIconButtonLabelRule.ruleIdStatic, makeRule().ruleId);
  });

  test('category is RuleCategory.accessibility', () {
    expect(makeRule().category, RuleCategory.accessibility);
  });

  // ---------------------------------------------------------------------------
  // AC1: Positive — IconButton without tooltip/Semantics → finding
  // ---------------------------------------------------------------------------

  test(
    'AC1: IconButton without tooltip and without Semantics → exactly one finding',
    () {
      final findings = makeRule().run(loadResult);
      final iconButtonFindings = findings
          .where((f) => f.filePath.contains('icon_button_missing_label'))
          .toList();
      expect(
        iconButtonFindings,
        hasLength(1),
        reason:
            'Expected exactly 1 finding for icon_button_missing_label.dart. '
            'Got: ${iconButtonFindings.map((f) => f.message).join(", ")}',
      );
    },
  );

  test('AC1: finding ruleId is a11y-icon-button-label', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, 'a11y-icon-button-label');
    }
  });

  test('AC1: finding severity is Severity.warning', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.severity, Severity.warning);
    }
  });

  test('AC1: finding kind is "missing-accessible-name"', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.kind, 'missing-accessible-name');
    }
  });

  test('AC1: finding message mentions IconButton', () {
    final findings = makeRule().run(loadResult);
    final iconBtnMsg = findings
        .where((f) => f.filePath.contains('icon_button_missing_label'))
        .map((f) => f.message)
        .first;
    expect(iconBtnMsg, contains('IconButton'));
  });

  // ---------------------------------------------------------------------------
  // AC2: Positive — GestureDetector/InkWell with pure Icon child → findings
  // ---------------------------------------------------------------------------

  test('AC2: GestureDetector with Icon child → one finding', () {
    final findings = makeRule().run(loadResult);
    final gestureFindings = findings
        .where(
          (f) =>
              f.filePath.contains('gesture_and_inkwell') &&
              f.message.contains('GestureDetector'),
        )
        .toList();
    expect(
      gestureFindings,
      hasLength(1),
      reason: 'Expected 1 finding for GestureDetector with Icon child',
    );
  });

  test('AC2: InkWell with Icon child → one finding', () {
    final findings = makeRule().run(loadResult);
    final inkWellFindings = findings
        .where(
          (f) =>
              f.filePath.contains('gesture_and_inkwell') &&
              f.message.contains('InkWell'),
        )
        .toList();
    expect(
      inkWellFindings,
      hasLength(1),
      reason: 'Expected 1 finding for InkWell with Icon child',
    );
  });

  test(
    'AC2: total findings count — 1 (IconButton) + 2 (GestureDetector, InkWell)',
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
  // AC3: Negative — tooltip OR Semantics(label:) → no finding
  // ---------------------------------------------------------------------------

  test('AC3: no findings for IconButton(tooltip: …)', () {
    final findings = makeRule().run(loadResult);
    final tooltipFindings = findings.where(
      (f) =>
          f.filePath.contains('icon_button_clean') &&
          f.message.contains('IconButton'),
    );
    // buildWithTooltip uses tooltip — no finding
    // buildIconButtonInSemantics uses Semantics wrapper — no finding
    // Check that the file produces zero IconButton findings in total.
    expect(
      tooltipFindings,
      isEmpty,
      reason: 'IconButton with tooltip must not be flagged',
    );
  });

  test('AC3: no findings for any widget in icon_button_clean.dart', () {
    final findings = makeRule().run(loadResult);
    final cleanFindings = findings.where(
      (f) => f.filePath.contains('icon_button_clean'),
    );
    expect(
      cleanFindings,
      isEmpty,
      reason:
          'icon_button_clean.dart contains only clean widgets '
          '(tooltip or Semantics wrapper) — zero findings expected',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4: Alias/codegen counter-example → no finding
  // ---------------------------------------------------------------------------

  test('AC4: local IconButton class (not package:flutter) → no finding', () {
    final findings = makeRule().run(loadResult);
    final aliasFindings = findings.where(
      (f) => f.filePath.contains('icon_button_alias'),
    );
    expect(
      aliasFindings,
      isEmpty,
      reason:
          'Local IconButton is not Flutter IconButton — must not be flagged',
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

  test('AC4: GestureDetector with non-Icon child → no finding', () {
    final findings = makeRule().run(loadResult);
    final nonIconFindings = findings.where(
      (f) => f.filePath.contains('non_icon_child'),
    );
    expect(
      nonIconFindings,
      isEmpty,
      reason: 'GestureDetector/InkWell with non-Icon child must not be flagged',
    );
  });

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

    test('AC5: wcagRef carries WCAG 4.1.2 data', () {
      final ref = sampleFinding.wcagRef!;
      expect(ref.number, '4.1.2');
      expect(ref.title, 'Name, Role, Value');
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
      expect(json, contains('"4.1.2"'));
      expect(json, contains('"Name, Role, Value"'));
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
      expect(sarif, contains('4.1.2'));
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
      expect(human, contains('WCAG 4.1.2'));
      expect(human, contains('Name, Role, Value'));
    });
  });

  // ---------------------------------------------------------------------------
  // AC6: remedy is non-empty and actionable
  // ---------------------------------------------------------------------------

  test('AC6: remedy is non-empty and actionable', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.remedy, isNotNull);
      expect(f.remedy, isNotEmpty);
    }
  });

  // ---------------------------------------------------------------------------
  // AC6: AnalysisRunner — rule participates in category-filtered a11y run
  // ---------------------------------------------------------------------------

  test('AC6: a11y-icon-button-label is in fullRegistryIds', () {
    expect(AnalysisRunner.fullRegistryIds, contains('a11y-icon-button-label'));
  });

  test('AC6: a11y-icon-button-label belongs to RuleCategory.accessibility', () {
    final a11yIds = AnalysisRunner.activeIdsForCategory(
      RuleCategory.accessibility,
    );
    expect(a11yIds, contains('a11y-icon-button-label'));
  });

  test(
    'AC6: AnalysisRunner with includeA11y:true includes a11y-icon-button-label',
    () {
      const config = LoamConfig.defaults();
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, contains('a11y-icon-button-label'));
    },
  );

  test(
    'AC6: AnalysisRunner with includeA11y:false excludes a11y-icon-button-label',
    () {
      const config = LoamConfig(
        ruleToggles: {},
        ignoreGlobs: [],
        includeA11y: false,
      );
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, isNot(contains('a11y-icon-button-label')));
    },
  );
}
