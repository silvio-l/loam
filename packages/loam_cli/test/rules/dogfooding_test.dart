@TestOn('vm')
library;

/// Self-dogfooding test: runs UnusedPublicExportsRule and
/// CircularDependenciesRule over the loam_cli package itself
/// (packages/loam_cli/) and asserts zero findings for each.
///
/// This is the Slice A acceptance criterion (AC5): each rule must be
/// conservative enough that it produces no false positives on the own
/// codebase. If a test fails, the rule must be made MORE conservative
/// (per PRD §12), not suppressed — or, for circular-dependencies, the
/// genuine self-cycle must be broken in production code.
import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/circular_dependencies_rule.dart';
import 'package:loam/src/rules/unused_public_exports_rule.dart';
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
}
