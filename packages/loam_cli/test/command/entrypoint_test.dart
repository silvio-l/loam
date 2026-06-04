@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// Import the testable `run` function directly from the entrypoint.
// Because `bin/` is not a library, we import it as a URI.
import '../../bin/loam.dart' as cli;

/// Creates a minimal Dart package with no public symbols (clean project).
/// Caller is responsible for deleting the returned directory.
Directory _makeCleanProject() {
  final dir = Directory.systemTemp.createTempSync('loam_entrypoint_test_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: clean_pkg
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  File(p.join(dir.path, 'lib', 'clean.dart')).writeAsStringSync('// empty\n');
  return dir;
}

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

    // scan is now implemented: exit 0 only when no findings are present.
    // Use a clean temporary project so the test is deterministic.
    test('scan subcommand → exit 0 on clean project', () async {
      final dir = _makeCleanProject();
      try {
        final code = await cli.run(['scan', '--project-root', dir.path]);
        expect(code, equals(0));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('health subcommand → exit 0 (stub)', () async {
      final code = await cli.run(['health']);
      expect(code, equals(0));
    });

    test('gate subcommand → exit 0 (stub)', () async {
      final code = await cli.run(['gate']);
      expect(code, equals(0));
    });

    // baseline is now implemented: no baseline.json → exit 1 (clear error)
    // See baseline_command_test.dart for full coverage.
    test(
      'baseline subcommand with no baseline.json → exit 1 (missing error)',
      () async {
        final dir = _makeCleanProject();
        try {
          final code = await cli.run(['baseline', '--project-root', dir.path]);
          expect(code, equals(1));
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );

    test('baseline --write → exit 0 (implemented)', () async {
      final dir = _makeCleanProject();
      try {
        final code = await cli.run([
          'baseline',
          '--write',
          '--project-root',
          dir.path,
        ]);
        expect(code, equals(0));
      } finally {
        dir.deleteSync(recursive: true);
      }
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
    // AC1: --help lists all 7 commands.
    // AC5 (stub commands only): all remaining stubs exit 0 + emit
    // "not yet implemented". scan is now implemented and excluded from those
    // expectations.
    const allCommands = [
      'scan',
      'health',
      'gate',
      'baseline',
      'slop',
      'init',
      'fix',
    ];

    // Stub commands (everything except scan and baseline which are now implemented).
    const stubCommands = ['health', 'gate', 'slop', 'init', 'fix'];

    test('all seven commands are registered (--help lists them)', () {
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

    test('each stub command exits 0 and emits "not yet implemented"', () {
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      for (final cmd in stubCommands) {
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
    late Directory cleanDir;

    setUpAll(() {
      cleanDir = _makeCleanProject();
    });

    tearDownAll(() {
      cleanDir.deleteSync(recursive: true);
    });

    test('default (no flag) → exit 0 on clean project', () async {
      final code = await cli.run(['scan', '--project-root', cleanDir.path]);
      expect(code, equals(0));
    });

    for (final fmt in ['human', 'sarif', 'json', 'markdown', 'html']) {
      test('--format=$fmt → exit 0 on clean project', () async {
        final code = await cli.run([
          '--format=$fmt',
          'scan',
          '--project-root',
          cleanDir.path,
        ]);
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
