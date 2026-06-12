@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;

/// In-process E2E matrix: drives the real CLI entrypoint (`cli.run`) across
/// every command × format and asserts the **exit-code contract**. This is the
/// fast, broad half of the push gate (the binary/SDK/PATH half lives in
/// `tool/e2e.sh`). It checks exit codes only — output prose is covered by the
/// per-reporter CLI tests and is intentionally not re-asserted here so the
/// matrix survives message-wording changes.
void main() {
  final fix = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    ),
  );

  late Directory clean;

  setUpAll(() {
    clean = Directory.systemTemp.createTempSync('loam_e2e_clean_');
    File(p.join(clean.path, 'pubspec.yaml')).writeAsStringSync('''
name: clean_project
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
    Directory(p.join(clean.path, 'lib')).createSync();
    File(
      p.join(clean.path, 'lib', 'clean.dart'),
    ).writeAsStringSync('// intentionally empty\n');
  });

  tearDownAll(() => clean.deleteSync(recursive: true));

  group('scan × formats (fixture with findings → exit 1)', () {
    for (final format in ['human', 'sarif', 'json', 'markdown']) {
      test('scan --format $format → exit 1', () async {
        final code = await cli.run([
          'scan',
          '--format',
          format,
          '--project-root',
          fix,
        ]);
        expect(code, 1);
      });
    }

    test('scan --format html (to temp file, no-open) → exit 1', () async {
      final out = Directory.systemTemp.createTempSync('loam_e2e_html_');
      try {
        final code = await cli.run([
          'scan',
          '--format',
          'html',
          '--no-open',
          '--output',
          p.join(out.path, 'r.html'),
          '--project-root',
          fix,
        ]);
        expect(code, 1);
        expect(File(p.join(out.path, 'r.html')).existsSync(), isTrue);
      } finally {
        out.deleteSync(recursive: true);
      }
    });

    test('scan on clean project → exit 0', () async {
      expect(await cli.run(['scan', '--project-root', clean.path]), 0);
    });
  });

  group('health', () {
    test('health on fixture → exit 0', () async {
      expect(await cli.run(['health', '--project-root', fix]), 0);
    });
    test('health on clean → exit 0', () async {
      expect(await cli.run(['health', '--project-root', clean.path]), 0);
    });
  });

  group('gate', () {
    test('gate without baseline → exit 1', () async {
      expect(await cli.run(['gate', '--project-root', clean.path]), 1);
    });
    test('gate --absolute on clean (greenfield) → exit 0', () async {
      expect(
        await cli.run(['gate', '--absolute', '--project-root', clean.path]),
        0,
      );
    });
    test('gate --absolute on findings → exit 1', () async {
      expect(await cli.run(['gate', '--absolute', '--project-root', fix]), 1);
    });

    test('lifecycle: baseline --write → gate green', () async {
      final copy = Directory.systemTemp.createTempSync('loam_e2e_fixcopy_');
      try {
        // Replicate the fixture into a writable temp dir.
        for (final entity in Directory(
          fix,
        ).listSync(recursive: true, followLinks: false)) {
          final rel = p.relative(entity.path, from: fix);
          final dest = p.join(copy.path, rel);
          if (entity is Directory) {
            Directory(dest).createSync(recursive: true);
          } else if (entity is File) {
            Directory(p.dirname(dest)).createSync(recursive: true);
            entity.copySync(dest);
          }
        }
        expect(
          await cli.run(['baseline', '--write', '--project-root', copy.path]),
          0,
        );
        expect(File(p.join(copy.path, 'baseline.json')).existsSync(), isTrue);
        expect(await cli.run(['gate', '--project-root', copy.path]), 0);
        expect(await cli.run(['baseline', '--project-root', copy.path]), 0);
      } finally {
        copy.deleteSync(recursive: true);
      }
    });
  });

  group('init', () {
    test('init scaffolds loam.yaml → exit 0', () async {
      final target = Directory.systemTemp.createTempSync('loam_e2e_init_');
      try {
        File(p.join(target.path, 'pubspec.yaml')).writeAsStringSync('''
name: init_target
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
        final code = await cli.run(['init', '--project-root', target.path]);
        expect(code, 0);
        expect(File(p.join(target.path, 'loam.yaml')).existsSync(), isTrue);
      } finally {
        target.deleteSync(recursive: true);
      }
    });
  });

  group('stub commands → EX_USAGE (64)', () {
    test('slop → exit 64', () async {
      expect(await cli.run(['slop', '--project-root', fix]), 64);
    });
    test('fix → exit 64', () async {
      expect(await cli.run(['fix', '--project-root', fix]), 64);
    });
  });

  group('global --version → exit 0 (short-circuit, no command)', () {
    test('--version → exit 0', () async {
      expect(await cli.run(['--version']), 0);
    });
  });

  group('usage errors → EX_USAGE (64)', () {
    test('unknown --format → exit 64', () async {
      expect(
        await cli.run(['scan', '--format', 'bogus', '--project-root', fix]),
        64,
      );
    });
    test('two positionals → exit 64', () async {
      expect(await cli.run(['scan', fix, clean.path]), 64);
    });
    test('unknown command → exit 64', () async {
      expect(await cli.run(['nonsense-command']), 64);
    });
  });
}
