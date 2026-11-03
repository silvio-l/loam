@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_runner.dart';
import '../support/shared_store.dart';

/// Hand-over point: the `--format agent` / `--max-findings` flags and the
/// documented exit codes, exercised through the real entry point in-process.
void main() {
  useSharedAnalyzerStore();

  final fixture = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'unused_exports_fixture',
  );

  Future<CliResult> loam(List<String> args) =>
      runCli(['--no-update-check', ...args]);

  test(
    'scan --format agent --max-findings 1 lists one, reports the rest',
    () async {
      final r = await loam([
        '--format',
        'agent',
        '--max-findings',
        '1',
        'scan',
        fixture,
      ]);
      expect(r.exitCode, 1);
      final listed = r.stdout
          .split('\n')
          .where((l) => RegExp(r'^(error|warning|info) ').hasMatch(l));
      expect(listed, hasLength(1));
      expect(r.stdout, contains('--max-findings 0'));
    },
  );

  test('scan --format agent --max-findings 0 omits nothing', () async {
    final r = await loam([
      '--format',
      'agent',
      '--max-findings',
      '0',
      'scan',
      fixture,
    ]);
    expect(r.exitCode, 1);
    expect(r.stdout, isNot(contains('--max-findings')));
  });

  for (final bad in ['-1', 'abc']) {
    test('--max-findings $bad is a usage error (exit 64)', () async {
      final r = await loam(['--max-findings', bad, 'scan', fixture]);
      expect(r.exitCode, 64);
    });
  }

  test(
    'other formats ignore --max-findings and still list everything',
    () async {
      final all = await loam(['--format', 'json', 'scan', fixture]);
      final capped = await loam([
        '--format',
        'json',
        '--max-findings',
        '1',
        'scan',
        fixture,
      ]);
      expect(capped.stdout, all.stdout);
    },
  );
}
