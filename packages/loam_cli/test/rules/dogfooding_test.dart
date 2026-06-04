@TestOn('vm')
library;

/// Self-dogfooding test: runs UnusedPublicExportsRule over the loam_cli
/// package itself (packages/loam_cli/) and asserts zero findings.
///
/// This is the Slice A acceptance criterion (AC5): the rule must be
/// conservative enough that it produces no false positives on the own
/// codebase. If this test fails, the rule must be made MORE conservative
/// (per PRD §12), not suppressed.
import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
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
  // AC5: The rule reports ZERO findings on the loam_cli codebase itself.
  // ---------------------------------------------------------------------------
  test(
    'AC5-dogfooding: UnusedPublicExportsRule reports zero findings on loam_cli/',
    () {
      final rule = UnusedPublicExportsRule(projectRoot: loamCliRoot);
      final findings = rule.run(loadResult);

      if (findings.isNotEmpty) {
        final details = findings
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: rule reported ${findings.length} finding(s) '
          'on loam_cli/. Per PRD §12, make the rule more conservative rather '
          'than adding suppression:\n$details',
        );
      }

      expect(findings, isEmpty);
    },
  );
}
