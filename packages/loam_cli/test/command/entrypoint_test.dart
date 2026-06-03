@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

// Import the testable `run` function directly from the entrypoint.
// Because `bin/` is not a library, we import it as a URI.
import '../../bin/loam.dart' as cli;

void main() {
  group('run() exit-code convention', () {
    test('empty args (no subcommand) → exit 0 (prints usage)', () async {
      // `args` returns null when no subcommand; runner maps null → 0.
      final code = await cli.run([]);
      expect(code, equals(0));
    });

    test('--help flag → exit 0', () async {
      final code = await cli.run(['--help']);
      expect(code, equals(0));
    });

    test('unknown flag → exit 64 (UsageException)', () async {
      final code = await cli.run(['--does-not-exist']);
      expect(code, equals(64));
    });

    test('scan subcommand → exit 0 (stub)', () async {
      final code = await cli.run(['scan']);
      expect(code, equals(0));
    });

    test('health subcommand → exit 0 (stub)', () async {
      final code = await cli.run(['health']);
      expect(code, equals(0));
    });

    test('gate subcommand → exit 0 (stub)', () async {
      final code = await cli.run(['gate']);
      expect(code, equals(0));
    });

    test('baseline subcommand → exit 0 (stub)', () async {
      final code = await cli.run(['baseline']);
      expect(code, equals(0));
    });

    test('baseline --write → exit 0 (stub)', () async {
      final code = await cli.run(['baseline', '--write']);
      expect(code, equals(0));
    });

    test('slop subcommand → exit 0 (stub)', () async {
      final code = await cli.run(['slop']);
      expect(code, equals(0));
    });

    test('init subcommand → exit 0 (stub)', () async {
      final code = await cli.run(['init']);
      expect(code, equals(0));
    });

    test('fix subcommand → exit 0 (stub)', () async {
      final code = await cli.run(['fix']);
      expect(code, equals(0));
    });
  });

  group('CLI surface smoke test (AC1 + AC5)', () {
    // AC1: --help lists all 7 commands; AC5: each stub exits 0 + emits
    // "not yet implemented".
    const allCommands = [
      'scan',
      'health',
      'gate',
      'baseline',
      'slop',
      'init',
      'fix',
    ];

    test('all seven commands are registered and exit 0', () async {
      for (final cmd in allCommands) {
        final code = await cli.run([cmd]);
        expect(code, equals(0), reason: 'command "$cmd" should exit 0');
      }
    });

    test('--help output lists all seven command names', () {
      // dart test runs with cwd = packages/loam_cli/; bin/ is directly beneath.
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--help',
      ]);
      final output = result.stdout as String;
      for (final cmd in allCommands) {
        expect(
          output,
          contains(cmd),
          reason: '--help output should list command "$cmd"',
        );
      }
    });

    test('each stub emits "not yet implemented" (subprocess)', () {
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      for (final cmd in allCommands) {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          cmd,
        ]);
        expect(result.exitCode, equals(0), reason: '"$cmd" should exit 0');
        expect(
          result.stdout as String,
          contains('not yet implemented'),
          reason: '"$cmd" should emit "not yet implemented"',
        );
      }
    });
  });

  group('--format flag', () {
    test('default (no flag) → exit 0', () async {
      final code = await cli.run(['scan']);
      expect(code, equals(0));
    });

    for (final fmt in ['human', 'sarif', 'json', 'markdown', 'html']) {
      test('--format=$fmt → exit 0', () async {
        final code = await cli.run(['--format=$fmt', 'scan']);
        expect(code, equals(0));
      });
    }

    test('invalid --format value → exit 64 (UsageException)', () async {
      final code = await cli.run(['--format=xml', 'scan']);
      expect(code, equals(64));
    });

    test('invalid --format value (txt) → exit 64', () async {
      final code = await cli.run(['--format=txt', 'scan']);
      expect(code, equals(64));
    });
  });
}
