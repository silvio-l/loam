@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// CLI integration test: `loam scan --format sarif` end-to-end via subprocess
/// against `test/fixtures/unused_exports_fixture`.
///
/// Mirrors the approach in `test/report/human_reporter_cli_test.dart`:
/// a real subprocess is forked so stdout is captured cleanly (no TTY,
/// so isTty=false → no ANSI escapes).
void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    ),
  );

  final entrypoint = p.join(Directory.current.path, 'bin', 'loam.dart');

  late JsonSchema sarifSchema;

  setUpAll(() async {
    final schemaPath = p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'sarif',
      'sarif-schema-2.1.0.json',
    );
    final schemaJson =
        jsonDecode(File(schemaPath).readAsStringSync()) as Map<String, dynamic>;
    sarifSchema = JsonSchema.create(schemaJson);
  });

  // -------------------------------------------------------------------------
  // AC8: loam scan --format sarif end-to-end
  // -------------------------------------------------------------------------

  test('loam scan --format sarif: exit 1 for fixture with findings', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'sarif',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    expect(
      result.exitCode,
      equals(1),
      reason: 'should exit 1 when findings are present',
    );
  });

  test('loam scan --format sarif: stdout is parseable JSON', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'sarif',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    expect(
      () => jsonDecode(out),
      returnsNormally,
      reason: 'output must be valid JSON',
    );
  });

  test('loam scan --format sarif: stdout is schema-valid SARIF 2.1.0', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'sarif',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    final doc = jsonDecode(out);
    final validationResult = sarifSchema.validate(doc);
    expect(
      validationResult.isValid,
      isTrue,
      reason:
          'loam scan --format sarif output must be schema-valid SARIF 2.1.0. '
          'Errors: ${validationResult.errors}',
    );
  });

  test('loam scan --format sarif: output contains "loam" tool name', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'sarif',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    final doc = jsonDecode(out) as Map<String, dynamic>;
    final driver =
        ((doc['runs'] as List).first as Map<String, dynamic>)['tool']['driver']
            as Map<String, dynamic>;
    expect(driver['name'], equals('loam'));
  });

  test(
    'loam scan --format sarif: results contain unused-public-exports ruleId',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'sarif',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      final doc = jsonDecode(out) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      final ruleIds = results
          .map((r) => (r as Map)['ruleId'] as String)
          .toList();
      expect(
        ruleIds,
        contains('unused-public-exports'),
        reason: 'SARIF results must include the unused-public-exports ruleId',
      );
    },
  );

  test(
    'loam scan --format sarif: URIs are relative (no absolute paths in output)',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'sarif',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      // The fixture path should not appear as an absolute path in the content
      expect(
        out,
        isNot(contains(fixturePath)),
        reason: 'absolute project root path must not appear in SARIF content',
      );
    },
  );
}
