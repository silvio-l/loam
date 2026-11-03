@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_runner.dart';
import '../support/shared_store.dart';

/// Machine-readable contracts of `loam scan` output, through the real entry
/// point in-process: the JSON envelope, schema-valid SARIF 2.1.0, and the HTML
/// file hand-over. One scan per format for the whole file. Presentation (human,
/// markdown, HTML layout) is intentionally not asserted; format dispatch and
/// exit codes live in `test/e2e/cli_matrix_test.dart`.
void main() {
  useSharedAnalyzerStore();

  final fixture = p.normalize(
    p.join('test', 'fixtures', 'unused_exports_fixture'),
  );
  final fixtureAbs = p.absolute(fixture);

  late CliResult jsonRun;
  late CliResult sarifRun;
  late Directory out;
  late String htmlOut;
  late CliResult htmlRun;
  late JsonSchema sarifSchema;

  setUpAll(() async {
    sarifSchema = JsonSchema.create(
      jsonDecode(
            File(
              p.join('test', 'fixtures', 'sarif', 'sarif-schema-2.1.0.json'),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    out = Directory.systemTemp.createTempSync('loam_output_contract_');
    htmlOut = p.join(out.path, 'nested', 'report.html');
    Directory(p.dirname(htmlOut)).createSync(recursive: true);

    jsonRun = await runCli([
      '--format',
      'json',
      'scan',
      '--project-root',
      fixtureAbs,
    ]);
    sarifRun = await runCli([
      '--format',
      'sarif',
      'scan',
      '--project-root',
      fixtureAbs,
    ]);
    htmlRun = await runCli([
      '--format',
      'html',
      '--output',
      htmlOut,
      'scan',
      '--project-root',
      fixtureAbs,
    ]);
  });

  tearDownAll(() => out.deleteSync(recursive: true));

  group('json', () {
    late Map<String, dynamic> doc;
    setUpAll(() => doc = jsonDecode(jsonRun.stdout) as Map<String, dynamic>);

    test('exit 1 with findings, envelope schemaVersion 3', () {
      expect(jsonRun.exitCode, 1);
      expect(doc['schemaVersion'], 3);
      expect((doc['tool'] as Map)['name'], 'loam');
    });

    test('summary and scan scope fields', () {
      final summary = doc['summary'] as Map<String, dynamic>;
      for (final key in ['total', 'error', 'warning', 'info', 'suppressed']) {
        expect(summary[key], isA<int>(), reason: key);
      }
      final scan = doc['scan'] as Map<String, dynamic>;
      for (final key in [
        'filesAnalyzed',
        'libFilesAnalyzed',
        'linesAnalyzed',
      ]) {
        expect(scan[key], isA<int>(), reason: key);
      }
      expect(scan['rulesRun'], isA<List<dynamic>>());
    });

    test('findings carry ruleId, kind and remedy', () {
      final findings = (doc['findings'] as List).cast<Map<String, dynamic>>();
      expect(findings, isNotEmpty);
      for (final f in findings) {
        expect(f['kind'], isNotNull);
        expect(f['remedy'], isNotNull);
      }
      expect(
        findings.map((f) => f['ruleId']),
        contains('unused-public-exports'),
      );
    });

    test('no absolute project path leaks into the output', () {
      expect(jsonRun.stdout, isNot(contains(fixtureAbs)));
    });
  });

  group('sarif', () {
    test('exit 1 and schema-valid SARIF 2.1.0', () {
      expect(sarifRun.exitCode, 1);
      final result = sarifSchema.validate(jsonDecode(sarifRun.stdout));
      expect(result.isValid, isTrue, reason: '${result.errors}');
    });

    test('tool name, rule ids, relative URIs', () {
      final run =
          (jsonDecode(sarifRun.stdout)['runs'] as List).first
              as Map<String, dynamic>;
      expect(run['tool']['driver']['name'], 'loam');
      final ruleIds = (run['results'] as List).map((r) => (r as Map)['ruleId']);
      expect(ruleIds, contains('unused-public-exports'));
      expect(sarifRun.stdout, isNot(contains(fixtureAbs)));
    });
  });

  group('html', () {
    test('--output writes the report file, stdout stays free of HTML', () {
      expect(htmlRun.exitCode, 1);
      expect(File(htmlOut).existsSync(), isTrue);
      expect(htmlRun.stdout, isNot(contains('<!DOCTYPE html>')));
    });

    test('self-contained: no external resources, no absolute paths', () {
      final html = File(htmlOut).readAsStringSync();
      expect(
        html,
        isNot(matches(RegExp(r'src\s*=\s*"https?://', caseSensitive: false))),
      );
      expect(
        html,
        isNot(
          matches(
            RegExp(r'<link[^>]+href\s*=\s*"https?://', caseSensitive: false),
          ),
        ),
      );
      expect(html, isNot(contains(fixtureAbs)));
    });
  });
}
