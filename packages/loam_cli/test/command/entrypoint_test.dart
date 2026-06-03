@TestOn('vm')
library;

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
