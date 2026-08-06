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
import 'package:loam/src/rules/a11y_interactive_semantics_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'a11y_interactive_semantics_fixture',
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

  A11yInteractiveSemanticsRule makeRule() =>
      A11yInteractiveSemanticsRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // Interface contract
  // ---------------------------------------------------------------------------

  test('ruleId is a11y-interactive-semantics', () {
    expect(makeRule().ruleId, 'a11y-interactive-semantics');
  });

  test('static ruleIdStatic matches ruleId', () {
    expect(A11yInteractiveSemanticsRule.ruleIdStatic, makeRule().ruleId);
  });

  test('category is RuleCategory.accessibility', () {
    expect(makeRule().category, RuleCategory.accessibility);
  });

  // ---------------------------------------------------------------------------
  // AC1: Positive — custom widget with onTap without Semantics → one finding
  // ---------------------------------------------------------------------------

  test('AC1: CustomCard with onTap but no Semantics wrapper → one finding', () {
    final findings = makeRule().run(loadResult);
    final positiveFindings = findings
        .where((f) => f.filePath.contains('custom_widget_positive'))
        .toList();
    expect(
      positiveFindings,
      hasLength(1),
      reason:
          'Expected exactly 1 finding in custom_widget_positive.dart '
          '(CustomCard with onTap, no Semantics wrapper). '
          'Got: ${positiveFindings.map((f) => f.message).join(", ")}',
    );
  });

  test('AC1: finding ruleId is a11y-interactive-semantics', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, 'a11y-interactive-semantics');
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

  test('AC1: finding message mentions the widget name and WCAG 4.1.2', () {
    final findings = makeRule().run(loadResult);
    final positiveFindings = findings
        .where((f) => f.filePath.contains('custom_widget_positive'))
        .toList();
    expect(positiveFindings, isNotEmpty);
    final f = positiveFindings.first;
    expect(
      f.message,
      contains('CustomCard'),
      reason: 'Message must mention the widget class name: ${f.message}',
    );
    expect(
      f.message,
      contains('4.1.2'),
      reason: 'Message must reference WCAG 4.1.2: ${f.message}',
    );
  });

  test('AC1: finding remedy mentions Semantics', () {
    final findings = makeRule().run(loadResult);
    final positiveFindings = findings
        .where((f) => f.filePath.contains('custom_widget_positive'))
        .toList();
    expect(positiveFindings, isNotEmpty);
    expect(positiveFindings.first.remedy, contains('Semantics'));
  });

  // ---------------------------------------------------------------------------
  // AC2: Negative — Semantics(label:) wrapper → no finding
  // ---------------------------------------------------------------------------

  test('AC2: no findings in custom_widget_clean.dart', () {
    final findings = makeRule().run(loadResult);
    final cleanFindings = findings.where(
      (f) => f.filePath.contains('custom_widget_clean'),
    );
    expect(
      cleanFindings,
      isEmpty,
      reason:
          'custom_widget_clean.dart wraps CustomCard in Semantics(label:) '
          '— zero findings expected',
    );
  });

  // ---------------------------------------------------------------------------
  // AC3: Overlap exclusion — IconButton and TextField → no finding from THIS rule
  // ---------------------------------------------------------------------------

  test('AC3: IconButton (package:flutter) with onPressed → no finding from '
      'a11y-interactive-semantics', () {
    final findings = makeRule().run(loadResult);
    final overlapFindings = findings.where(
      (f) => f.filePath.contains('overlap_excluded'),
    );
    expect(
      overlapFindings,
      isEmpty,
      reason:
          'overlap_excluded.dart uses Flutter built-in widgets (IconButton, '
          'TextField) that are already covered by sibling rules — '
          'a11y-interactive-semantics must produce zero findings here',
    );
  });

  // ---------------------------------------------------------------------------
  // AC3b: Regression — Flutter Material buttons and self-labelled Semantics
  //        must NOT be flagged (FP root-fix for dogfood run 2025-06)
  // ---------------------------------------------------------------------------

  test(
    'AC3b: ElevatedButton and TextButton (package:flutter) with onPressed → '
    'no finding (ButtonStyleButton accessible name comes from child text)',
    () {
      final findings = makeRule().run(loadResult);
      final buttonFindings = findings.where(
        (f) => f.filePath.contains('flutter_builtin_buttons'),
      );
      expect(
        buttonFindings,
        isEmpty,
        reason:
            'flutter_builtin_buttons.dart uses ElevatedButton, TextButton, '
            'and Semantics — all from package:flutter and excluded from this '
            'rule. Zero findings expected.',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // AC4: Alias/codegen — generated file → no finding
  // ---------------------------------------------------------------------------

  test('AC4: generated file (*.g.dart) → no finding', () {
    final findings = makeRule().run(loadResult);
    final generatedFindings = findings.where(
      (f) => f.filePath.endsWith('.g.dart'),
    );
    expect(
      generatedFindings,
      isEmpty,
      reason: 'Generated files must be skipped entirely',
    );
  });

  // ---------------------------------------------------------------------------
  // AC7: Call-site accessible-name property (label/semanticLabel/tooltip)
  //      — FP root-fix for field-findings 2026-06-23 (LottiButton) and
  //      2026-08-06 (WpButton): a widget that self-wraps in Semantics(...)
  //      internally, or delegates to an already-excluded Flutter widget, is
  //      indistinguishable from any other custom widget at the AST level —
  //      but both real-world shapes pass their accessible name through a
  //      `label:` call-site argument, which the rule now recognises directly.
  // ---------------------------------------------------------------------------

  test('AC7: no findings in label_property_self_wrapped_clean.dart '
      '(LottiButton shape: self-wraps in Semantics internally, label: at '
      'call site)', () {
    final findings = makeRule().run(loadResult);
    final cleanFindings = findings.where(
      (f) => f.filePath.contains('label_property_self_wrapped_clean'),
    );
    expect(cleanFindings, isEmpty);
  });

  test('AC7: no findings in label_property_delegating_clean.dart '
      '(WpButton shape: delegates to an already-excluded Flutter widget, '
      'label: at call site)', () {
    final findings = makeRule().run(loadResult);
    final cleanFindings = findings.where(
      (f) => f.filePath.contains('label_property_delegating_clean'),
    );
    expect(cleanFindings, isEmpty);
  });

  test('AC7: no findings in label_property_variants_clean.dart '
      '(semanticLabel: and tooltip: are also recognised)', () {
    final findings = makeRule().run(loadResult);
    final cleanFindings = findings.where(
      (f) => f.filePath.contains('label_property_variants_clean'),
    );
    expect(cleanFindings, isEmpty);
  });

  test(
    'AC7: one finding in label_property_empty_positive.dart '
    "(label: '' is empty — must still be flagged, conservative by design)",
    () {
      final findings = makeRule().run(loadResult);
      final positiveFindings = findings.where(
        (f) => f.filePath.contains('label_property_empty_positive'),
      );
      expect(positiveFindings, hasLength(1));
    },
  );

  // ---------------------------------------------------------------------------
  // Total finding count sanity check
  // ---------------------------------------------------------------------------

  test('total findings: exactly 2 (custom_widget_positive.dart + '
      'label_property_empty_positive.dart)', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings,
      hasLength(2),
      reason:
          'Expected exactly 2 findings total. '
          'Got: ${findings.map((f) => "${f.filePath}:${f.line} ${f.message}").join("; ")}',
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
  // AC5: remedy is non-empty and actionable
  // ---------------------------------------------------------------------------

  test('AC5: remedy is non-empty and mentions Semantics', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.remedy, isNotNull);
      expect(f.remedy, isNotEmpty);
      expect(f.remedy, contains('Semantics'));
    }
  });

  // ---------------------------------------------------------------------------
  // AC6: AnalysisRunner — rule participates in registry and category filter
  // ---------------------------------------------------------------------------

  test('AC6: a11y-interactive-semantics is in fullRegistryIds', () {
    expect(
      AnalysisRunner.fullRegistryIds,
      contains('a11y-interactive-semantics'),
    );
  });

  test(
    'AC6: a11y-interactive-semantics belongs to RuleCategory.accessibility',
    () {
      final a11yIds = AnalysisRunner.activeIdsForCategory(
        RuleCategory.accessibility,
      );
      expect(a11yIds, contains('a11y-interactive-semantics'));
    },
  );

  test('AC6: AnalysisRunner with includeA11y:true includes '
      'a11y-interactive-semantics', () {
    const config = LoamConfig.defaults();
    final ids = AnalysisRunner.activeRuleIdsForConfig(config);
    expect(ids, contains('a11y-interactive-semantics'));
  });

  test('AC6: AnalysisRunner with includeA11y:false excludes '
      'a11y-interactive-semantics', () {
    const config = LoamConfig(
      ruleToggles: {},
      ignoreGlobs: [],
      includeA11y: false,
    );
    final ids = AnalysisRunner.activeRuleIdsForConfig(config);
    expect(ids, isNot(contains('a11y-interactive-semantics')));
  });

  test('AC6: fullRegistryIds is sorted lexicographically '
      '(a11y-image-label before a11y-interactive-semantics)', () {
    final ids = AnalysisRunner.fullRegistryIds;
    final imageIdx = ids.indexOf('a11y-image-label');
    final interactiveIdx = ids.indexOf('a11y-interactive-semantics');
    expect(imageIdx, lessThan(interactiveIdx));
  });

  test('AC6: rule can be toggled off via loam.yaml ruleToggles', () {
    const config = LoamConfig(
      ruleToggles: {'a11y-interactive-semantics': false},
      ignoreGlobs: [],
      includeA11y: true,
    );
    final ids = AnalysisRunner.activeRuleIdsForConfig(config);
    expect(ids, isNot(contains('a11y-interactive-semantics')));
  });
}
