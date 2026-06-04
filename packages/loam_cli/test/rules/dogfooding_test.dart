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
  // AC5: The rule reports zero UNEXPECTED findings on the loam_cli codebase.
  //
  // KNOWN GENUINE FINDINGS (Slice B — member support, added in Issue 04):
  //
  //   • `Finding.severity` (lib/src/model/finding.dart) — The `severity` field
  //     is declared and constructor-initialized but never explicitly read
  //     anywhere in the current codebase (the gate/reporter layers are post-MVP
  //     stubs). Named-argument constructor calls (`severity: Severity.warning`)
  //     resolve to the `FieldFormalParameterElement`, not the `FieldElement`,
  //     so the UsageIndex does not count them as reads.
  //     This is a genuine finding. It is allowed here because fixing it would
  //     require adding a reader outside this issue's scope.
  //     TRACK: remove from allowlist when a reader is added (e.g. in reporter).
  //
  // Per Issue 04 instructions: "if they are genuine real findings the project
  // should fix, that's out of scope for a fixture-driven rule test — instead
  // adjust the dogfooding test's expectation deliberately and document why."
  // ---------------------------------------------------------------------------

  // Known genuine unused-member findings for loam_cli itself.
  // Each entry is a (filePath, message) pair — both must match for a finding
  // to be considered a deliberate allowance (path-relative, POSIX).
  //
  // TRACK: remove entries when the underlying issue is fixed in the codebase.
  const allowedFindings = {
    // `Finding.severity` is declared and constructor-initialized but never
    // explicitly READ anywhere in the current codebase (gate/reporter are
    // post-MVP stubs). Named-argument constructor calls (`severity: …`) resolve
    // to the `FieldFormalParameterElement`, not the `FieldElement`, so the
    // UsageIndex does not count them as reads.
    // Per Issue 04 instructions, genuine findings that require out-of-scope
    // fixes are tracked here rather than suppressed in the rule.
    ('lib/src/model/finding.dart', 'unused public field `severity`'),
  };

  test(
    'AC5-dogfooding: UnusedPublicExportsRule reports no unexpected findings on loam_cli/',
    () {
      final rule = UnusedPublicExportsRule(projectRoot: loamCliRoot);
      final allFindings = rule.run(loadResult);

      // Separate known genuine findings from unexpected ones.
      final unexpected = allFindings.where((f) {
        final key = (f.filePath, f.message);
        return !allowedFindings.contains(key);
      }).toList();

      if (unexpected.isNotEmpty) {
        final details = unexpected
            .map((f) => '  ${f.filePath}:${f.line} — ${f.message}')
            .join('\n');
        fail(
          'Self-dogfooding failed: rule reported ${unexpected.length} unexpected '
          'finding(s) on loam_cli/. Per PRD §12, make the rule more conservative '
          'rather than adding suppression:\n$details',
        );
      }

      expect(unexpected, isEmpty);
    },
  );
}
