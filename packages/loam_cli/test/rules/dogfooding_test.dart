@TestOn('vm')
library;

/// Self-dogfooding test: runs every shipped rule — the four drift rules
/// (UnusedPublicExportsRule, CircularDependenciesRule, CodeDuplicatesRule,
/// ComplexityHotspotsRule), the four accessibility rules (a11y-image-label,
/// a11y-icon-button-label, a11y-form-field-label, a11y-interactive-semantics),
/// and all three slop rules (slop-unjustified-ignore, slop-empty-catch,
/// slop-narrative-comment) —
/// over the loam_cli package itself (packages/loam_cli/) and asserts zero
/// findings on production code (lib/ + bin/) for each. loam is run against
/// itself as a standing baseline, not only against external repos.
///
/// This is the Slice A acceptance criterion (AC5): each rule must be
/// conservative enough that it produces no false positives on the own
/// codebase. If a test fails, the rule must be made MORE conservative
/// (per PRD §12), not suppressed — or, for circular-dependencies, the
/// genuine self-cycle must be broken in production code.
import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/a11y_form_field_label_rule.dart';
import 'package:loam/src/rules/a11y_icon_button_label_rule.dart';
import 'package:loam/src/rules/a11y_image_label_rule.dart';
import 'package:loam/src/rules/a11y_interactive_semantics_rule.dart';
import 'package:loam/src/rules/circular_dependencies_rule.dart';
import 'package:loam/src/rules/complexity_hotspots_rule.dart';
import 'package:loam/src/rules/slop_empty_catch_rule.dart';
import 'package:loam/src/rules/slop_narrative_comment_rule.dart';
import 'package:loam/src/rules/slop_unjustified_ignore_rule.dart';
import 'package:loam/src/rules/unused_public_exports_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // When `dart test` runs from packages/loam_cli/, Directory.current.path is
  // the package root itself (packages/loam_cli/).
  final loamCliRoot = p.normalize(Directory.current.path);

  // Sanity check: make sure we found the right directory.
  final pubspecFile = File(p.join(loamCliRoot, 'pubspec.yaml'));

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    expect(
      pubspecFile.existsSync(),
      isTrue,
      reason:
          'Self-dogfooding: pubspec.yaml not found at $loamCliRoot — '
          'check the path computation in dogfooding_test.dart',
    );

    final loader = ProjectLoader();
    loadResult = await loader.load(loamCliRoot);

    // The own codebase must load the lib/ and bin/ sources cleanly.
    // Errors on test/fixtures/** are acceptable because those sub-directories
    // contain nested Dart packages with their own pubspec.yaml, which the
    // loader cannot resolve from the enclosing context.
    final nonFixtureErrors = loadResult.errors.where((e) {
      final rel = p.relative(e.path, from: loamCliRoot);
      return !rel.startsWith('test${p.separator}fixtures');
    }).toList();
    if (nonFixtureErrors.isNotEmpty) {
      final errorMessages = nonFixtureErrors
          .map((e) => '  ${e.path}: ${e.reason}')
          .join('\n');
      fail(
        'Self-dogfooding: loam_cli source files loaded with errors — '
        'fix the code first:\n$errorMessages',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // AC5: The rule reports zero findings on the loam_cli codebase.
  //
  // `Finding.severity` was previously allowed here because gate/reporter layers
  // were post-MVP stubs. That assumption is now stale: HumanReporter reads
  // `f.severity` at human_reporter.dart:74 and SarifReporter reads it at
  // sarif_reporter.dart:65. No allowlist is needed — the field is genuinely
  // read and the rule should produce zero findings on this codebase.
  //
  // Per PRD §12: if this test fails, make the rule more conservative or fix
  // the production code. Do NOT re-add allowlist entries or suppress findings.
  // ---------------------------------------------------------------------------

  test(
    'AC5-dogfooding: UnusedPublicExportsRule reports no unexpected findings on loam_cli/',
    () {
      final rule = UnusedPublicExportsRule(projectRoot: loamCliRoot);
      final findings = rule.run(loadResult);

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: rule reported ${findings.length} unexpected '
          'finding(s) on loam_cli/. Per PRD §12, make the rule more conservative '
          'rather than adding suppression:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  // ---------------------------------------------------------------------------
  // The circular-dependencies rule reports zero findings on the loam_cli
  // codebase: loam.dev's own first-party lib/ libraries must stay cycle-free.
  //
  // Per PRD §12: if this test fails, loam_cli genuinely has a self-cycle — a
  // real product finding. Break the loop in production code; do NOT suppress
  // the finding to keep the test green.
  // ---------------------------------------------------------------------------

  test(
    'dogfooding: CircularDependenciesRule reports no unexpected findings on loam_cli/',
    () {
      final rule = CircularDependenciesRule(projectRoot: loamCliRoot);
      final findings = rule.run(loadResult);

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: rule reported ${findings.length} unexpected '
          'circular-dependency finding(s) on loam_cli/. Per PRD §12, break the '
          'cycle in production code rather than suppressing it. Involved files '
          'per cycle are listed in each message:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  // ---------------------------------------------------------------------------
  // The complexity-hotspots rule reports zero *unsuppressed* findings on the
  // loam_cli codebase.
  //
  // The test runs via [AnalysisRunner] (not the Rule directly) so that inline
  // `// loam-ignore: complexity-hotspots` directives on genuinely-complex
  // internal dispatch functions are respected. These suppressions are
  // intentional, reviewed, and carry documented reasons — they are NOT a
  // blanket disable.
  //
  // Per PRD §12: new unsuppressed findings must be resolved by either
  // (a) refactoring the complex function, or (b) adding a targeted
  // `// loam-ignore: complexity-hotspots – <reason>` on the declaration.
  // Do NOT disable the rule in loam.yaml (blanket bypass is forbidden).
  // ---------------------------------------------------------------------------

  test(
    'dogfooding: complexity-hotspots reports 0 unsuppressed findings on loam_cli/',
    () async {
      // Use AnalysisRunner so that inline suppressions are honoured.
      final runner = AnalysisRunner();
      final allFindings = await runner.run(loamCliRoot);
      final findings = allFindings
          .where((f) => f.ruleId == ComplexityHotspotsRule.ruleIdStatic)
          .toList();

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: rule reported ${findings.length} unsuppressed '
          'complexity-hotspots finding(s) on loam_cli/. Per PRD §12, either '
          'refactor the production function or add a targeted '
          '// loam-ignore: complexity-hotspots – <reason> on the declaration.\n'
          'Details:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  // ---------------------------------------------------------------------------
  // The code-duplicates rule reports zero *unsuppressed* findings on the
  // loam_cli lib/ codebase.
  //
  // The test runs via [AnalysisRunner] with [ignore_globs] covering test/**
  // so that fixture files (which intentionally contain duplicates) and test
  // helper files (which share boilerplate setup code by design) are excluded.
  // Only the production code under lib/ and bin/ is checked.
  //
  // Genuine lib/ duplicates are suppressed inline with reviewed
  // `// loam-ignore: code-duplicates – <reason>` directives. These suppressions
  // are intentional and carry a documented reason — they are NOT a blanket
  // disable.
  //
  // Per PRD §12: new unsuppressed lib/ findings must be resolved by either
  // (a) extracting the shared helper, or (b) adding a targeted
  // `// loam-ignore: code-duplicates – <reason>` on the function body.
  // Do NOT disable the rule globally or add test/ to ignore_globs in loam.yaml.
  // ---------------------------------------------------------------------------

  test(
    'dogfooding: code-duplicates reports 0 unsuppressed findings on loam_cli/lib/',
    () async {
      // Use AnalysisRunner with ignore_globs to scope to lib/ + bin/ only.
      // test/ is intentionally excluded: fixture files contain known duplicates
      // by design, and test helpers share boilerplate setup code that is fine
      // to repeat for readability without extraction.
      final config = LoamConfig(
        ruleToggles: const {},
        ignoreGlobs: const ['test/**'],
      );
      final runner = AnalysisRunner(config: config);
      final allFindings = await runner.run(loamCliRoot);
      final findings = allFindings
          .where((f) => f.ruleId == 'code-duplicates')
          .toList();

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: code-duplicates reported ${findings.length} '
          'unsuppressed finding(s) on loam_cli/lib/. Per PRD §12, either extract '
          'the shared helper into a common utility or add a targeted '
          '// loam-ignore: code-duplicates – <reason> on the function body.\n'
          'Details:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  // ---------------------------------------------------------------------------
  // The a11y-image-label rule reports zero findings on the loam_cli codebase.
  //
  // loam_cli uses no Flutter widgets — it is a pure Dart CLI — so the rule
  // must produce zero findings. Any finding here indicates a false positive
  // (e.g. a class named Image in a non-flutter package being misidentified).
  //
  // Per PRD §12: if this test fails, make the rule more conservative (tighten
  // the library URI check) rather than suppressing the finding.
  // ---------------------------------------------------------------------------

  test(
    'dogfooding: a11y-image-label reports 0 findings on loam_cli/lib + bin',
    () {
      final rule = A11yImageLabelRule(projectRoot: loamCliRoot);
      final rawFindings = rule.run(loadResult);

      // Exclude test/fixtures/**: the a11y_image_label_fixture intentionally
      // contains Flutter Image stubs (the rule's own test corpus). Only lib/
      // and bin/ (production code) must be clean.
      final findings = rawFindings.where((f) {
        final rel = f.filePath;
        return !rel.startsWith('test${p.separator}fixtures') &&
            !rel.startsWith('test/fixtures');
      }).toList();

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: a11y-image-label reported '
          '${findings.length} unexpected finding(s) on loam_cli/lib + bin. '
          'Per PRD §12, tighten the library URI check rather than adding '
          'suppression:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  test(
    'dogfooding: a11y-icon-button-label reports 0 findings on loam_cli/lib + bin',
    () {
      final rule = A11yIconButtonLabelRule(projectRoot: loamCliRoot);
      final rawFindings = rule.run(loadResult);

      // Exclude test/fixtures/**: the a11y_icon_button_label_fixture
      // intentionally contains Flutter IconButton/GestureDetector stubs (the
      // rule's own test corpus). Only lib/ and bin/ must be clean.
      final findings = rawFindings.where((f) {
        final rel = f.filePath;
        return !rel.startsWith('test${p.separator}fixtures') &&
            !rel.startsWith('test/fixtures');
      }).toList();

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: a11y-icon-button-label reported '
          '${findings.length} unexpected finding(s) on loam_cli/lib + bin. '
          'Per PRD §12, tighten the element-model check rather than adding '
          'suppression:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  test(
    'dogfooding: a11y-form-field-label reports 0 findings on loam_cli/lib + bin',
    () {
      final rule = A11yFormFieldLabelRule(projectRoot: loamCliRoot);
      final rawFindings = rule.run(loadResult);

      // Exclude test/fixtures/**: the a11y_form_field_label_fixture
      // intentionally contains Flutter TextField/TextFormField stubs (the
      // rule's own test corpus). Only lib/ and bin/ must be clean.
      final findings = rawFindings.where((f) {
        final rel = f.filePath;
        return !rel.startsWith('test${p.separator}fixtures') &&
            !rel.startsWith('test/fixtures');
      }).toList();

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: a11y-form-field-label reported '
          '${findings.length} unexpected finding(s) on loam_cli/lib + bin. '
          'Per PRD §12, tighten the element-model check rather than adding '
          'suppression:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  test(
    'dogfooding: a11y-interactive-semantics reports 0 findings on loam_cli/lib + bin',
    () {
      final rule = A11yInteractiveSemanticsRule(projectRoot: loamCliRoot);
      final rawFindings = rule.run(loadResult);

      // Exclude test/fixtures/**: the a11y_interactive_semantics_fixture
      // intentionally contains custom interactive-widget stubs (the rule's own
      // test corpus). Only lib/ and bin/ (production code) must be clean.
      // This is the standing guard against the 148-false-positive regression
      // the productive test (issue 06) fixed: if the package:flutter exclusion
      // ever re-broadens or breaks, this fails on loam_cli's own sources.
      final findings = rawFindings.where((f) {
        final rel = f.filePath;
        return !rel.startsWith('test${p.separator}fixtures') &&
            !rel.startsWith('test/fixtures');
      }).toList();

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: a11y-interactive-semantics reported '
          '${findings.length} unexpected finding(s) on loam_cli/lib + bin. '
          'Per PRD §12, tighten the element-model check rather than adding '
          'suppression:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  // ---------------------------------------------------------------------------
  // slop-unjustified-ignore: 0 findings on loam_cli/lib + bin.
  //
  // The loam_cli production code must carry no unjustified // ignore: or
  // // ignore_for_file: directives. Any such directive must either have an
  // inline justification or a comment on the line above explaining why.
  //
  // Per PRD §12: if this test fails, either add a justification comment or fix
  // the underlying issue. Do NOT suppress or disable the rule.
  // ---------------------------------------------------------------------------

  test(
    'dogfooding: slop-unjustified-ignore reports 0 findings on loam_cli/lib + bin',
    () {
      final rule = SlopUnjustifiedIgnoreRule(projectRoot: loamCliRoot);
      final rawFindings = rule.run(loadResult);

      // Exclude test/fixtures/**: fixture files intentionally contain
      // unjustified // ignore: directives as part of the rule's test corpus.
      // Only lib/ and bin/ (production code) must be clean.
      final findings = rawFindings.where((f) {
        final rel = f.filePath;
        return !rel.startsWith('test${p.separator}fixtures') &&
            !rel.startsWith('test/fixtures');
      }).toList();

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: slop-unjustified-ignore reported '
          '${findings.length} unexpected finding(s) on loam_cli/lib + bin. '
          'Per PRD §12, add a justification comment or fix the underlying issue:\n'
          '$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  // ---------------------------------------------------------------------------
  // slop-empty-catch: 0 unsuppressed findings on loam_cli/lib + bin.
  //
  // The loam_cli production code has a handful of intentional comment-only
  // catch blocks (symlink fallback, update-check swallow, cache-write swallow).
  // Each carries a `// loam-ignore: slop-empty-catch – <reason>` directive
  // on the line immediately before the `} catch` line. This test runs via
  // AnalysisRunner so those inline suppressions are honoured.
  //
  // test/** is excluded via ignore_globs: the slop_empty_catch_fixture
  // intentionally contains bare catch blocks as the rule's own test corpus.
  //
  // Per PRD §12: if this test fails, either add a loam-ignore with a
  // documented reason, add real error handling, or rethrow the exception.
  // ---------------------------------------------------------------------------

  test(
    'dogfooding: slop-empty-catch reports 0 unsuppressed findings on loam_cli/lib + bin',
    () async {
      // AnalysisRunner honours inline suppressions; direct Rule.run does not.
      // test/** excluded so the fixture corpus does not count.
      final config = LoamConfig(
        ruleToggles: const {},
        ignoreGlobs: const ['test/**'],
      );
      final runner = AnalysisRunner(config: config);
      final allFindings = await runner.run(loamCliRoot);
      final findings = allFindings
          .where((f) => f.ruleId == SlopEmptyCatchRule.ruleIdStatic)
          .toList();

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: slop-empty-catch reported '
          '${findings.length} unsuppressed finding(s) on loam_cli/lib + bin. '
          'Per PRD §12, either add a loam-ignore with a documented reason, '
          'add real error handling, or rethrow the exception:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );

  // ---------------------------------------------------------------------------
  // slop-narrative-comment: 0 findings on loam_cli/lib + bin.
  //
  // loam_cli production code must carry no // comments that trivially restate
  // a declaration name. Any such comment is either slop or should be turned
  // into a /// Dart-doc comment with real documentation.
  //
  // test/fixtures/** is excluded because the slop_narrative_comment_fixture
  // intentionally contains name-restatement comments as the rule's own
  // test corpus.
  //
  // Per PRD §12: if this test fails, remove the trivial comment or replace it
  // with a /// Dart-doc comment that adds real information.
  // ---------------------------------------------------------------------------

  test(
    'dogfooding: slop-narrative-comment reports 0 findings on loam_cli/lib + bin',
    () {
      final rule = SlopNarrativeCommentRule(projectRoot: loamCliRoot);
      final rawFindings = rule.run(loadResult);

      // Exclude test/fixtures/**: the slop_narrative_comment_fixture
      // intentionally contains name-restatement comments as the rule's own
      // test corpus. Only lib/ and bin/ (production code) must be clean.
      final findings = rawFindings.where((f) {
        final rel = f.filePath;
        return !rel.startsWith('test${p.separator}fixtures') &&
            !rel.startsWith('test/fixtures');
      }).toList();

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: slop-narrative-comment reported '
          '${findings.length} unexpected finding(s) on loam_cli/lib + bin. '
          'Per PRD §12, remove the trivial comment or replace it with a '
          '/// Dart-doc comment that adds real information:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );
}
