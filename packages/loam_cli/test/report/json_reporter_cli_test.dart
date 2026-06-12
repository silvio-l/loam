@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// CLI integration test: `loam scan --format json` end-to-end via subprocess
/// against `test/fixtures/unused_exports_fixture`.
///
/// Mirrors the approach in `test/report/sarif_reporter_cli_test.dart`:
/// a real subprocess is forked so stdout is captured cleanly (no TTY).
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

  // -------------------------------------------------------------------------
  // loam scan --format json: end-to-end
  // -------------------------------------------------------------------------

  test('loam scan --format json: exit 1 for fixture with findings', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'json',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    expect(
      result.exitCode,
      equals(1),
      reason:
          'should exit 1 when findings are present (reporter does not affect exit code)',
    );
  });

  test('loam scan --format json: stdout is parseable JSON', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'json',
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

  test('loam scan --format json: envelope has schemaVersion == 3', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'json',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    final doc = jsonDecode(out) as Map<String, dynamic>;
    expect(doc['schemaVersion'], equals(3));
    // Scope + suppression surfaced (schemaVersion 3 additions).
    final summary = doc['summary'] as Map<String, dynamic>;
    expect(summary['suppressed'], isA<int>());
    final scan = doc['scan'] as Map<String, dynamic>;
    expect(scan['filesAnalyzed'], isA<int>());
    expect(scan['libFilesAnalyzed'], isA<int>());
    expect(scan['linesAnalyzed'], isA<int>());
    expect(scan['rulesRun'], isA<List<dynamic>>());
  });

  test('loam scan --format json: findings carry kind + remedy (schema 2)', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'json',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    final doc = jsonDecode(out) as Map<String, dynamic>;
    final findings = (doc['findings'] as List).cast<Map<String, dynamic>>();
    expect(findings, isNotEmpty);
    for (final f in findings) {
      expect(f.containsKey('kind'), isTrue);
      expect(f.containsKey('remedy'), isTrue);
      expect(f['kind'], isNotNull);
      expect(f['remedy'], isNotNull);
    }
  });

  test('loam scan --format json: tool.name == "loam"', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'json',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    final doc = jsonDecode(out) as Map<String, dynamic>;
    expect((doc['tool'] as Map<String, dynamic>)['name'], equals('loam'));
  });

  test('loam scan --format json: summary has total, error, warning, info', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'json',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    final doc = jsonDecode(out) as Map<String, dynamic>;
    final summary = doc['summary'] as Map<String, dynamic>;
    expect(summary.containsKey('total'), isTrue);
    expect(summary.containsKey('error'), isTrue);
    expect(summary.containsKey('warning'), isTrue);
    expect(summary.containsKey('info'), isTrue);
  });

  test(
    'loam scan --format json: findings contain unused-public-exports ruleId',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'json',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      final doc = jsonDecode(out) as Map<String, dynamic>;
      final findings = doc['findings'] as List<dynamic>;
      final ruleIds = findings
          .map((f) => (f as Map<String, dynamic>)['ruleId'] as String)
          .toList();
      expect(
        ruleIds,
        contains('unused-public-exports'),
        reason: 'JSON findings must include the unused-public-exports ruleId',
      );
    },
  );

  test(
    'loam scan --format json: filePaths are relative (no absolute paths in output)',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'json',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      // The fixture path should not appear as an absolute path in the content.
      expect(
        out,
        isNot(contains(fixturePath)),
        reason: 'absolute project root path must not appear in JSON content',
      );
    },
  );

  // -------------------------------------------------------------------------
  // loam gate --format json: optional smoke test
  // -------------------------------------------------------------------------

  test('loam gate --format json --absolute: stdout is parseable JSON', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'json',
      'gate',
      '--absolute',
      '--project-root',
      fixturePath,
    ]);
    // gate --absolute with findings exits 1; output starts with the JSON report
    // followed by a gate summary line. We extract just the JSON prefix.
    final out = result.stdout as String;
    // The JSON block ends with the closing brace before the gate summary line.
    // Parse only the JSON part — find matching closing brace.
    final jsonEnd = out.lastIndexOf('}');
    if (jsonEnd >= 0) {
      final jsonPart = out.substring(0, jsonEnd + 1);
      expect(
        () => jsonDecode(jsonPart),
        returnsNormally,
        reason: 'JSON portion of gate output must be parseable',
      );
    }
  });
}
