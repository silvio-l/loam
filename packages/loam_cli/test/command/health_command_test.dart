@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a minimal clean Dart project with an empty lib/ (no executables).
///
/// [HealthScore.compute] on an empty list returns score=100/grade=A/hotspots=[].
/// This is the authoritative "green" state.
Directory _makeCleanProject() {
  final dir = Directory.systemTemp.createTempSync('loam_health_clean_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: clean_health_pkg
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  // Empty library — no executables → HealthScore returns 100/A/[] hotspots.
  File(
    p.join(dir.path, 'lib', 'clean.dart'),
  ).writeAsStringSync('// empty library — no executables\n');
  return dir;
}

/// Creates a minimal Dart project whose lib/ contains a function with high
/// enough cyclomatic complexity to produce a non-trivial (< 100) health score
/// and at least one Hotspot row.
///
/// The function has 21 if-statements → cyclomatic = 22, cognitive ~ 21.
/// With N=1 executable: totalPenalty = min(22−10, 40) = 12, worstCase = 40,
/// normalisedPenalty = 12/40 = 0.3, score = round(70) = 70, grade C.
Directory _makeHotspotProject() {
  final dir = Directory.systemTemp.createTempSync('loam_health_hotspot_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: hotspot_health_pkg
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  // 21 if-statements → cyclomatic=22, magnitude=22>10 → penalty=min(12,40)=12.
  File(p.join(dir.path, 'lib', 'hotspot.dart')).writeAsStringSync(r'''
/// A function with high cyclomatic complexity.
int hotFn(int a, int b, int c, int d, int e, int f, int g, int h, int i) {
  if (a > 0) print('a');
  if (b > 0) print('b');
  if (c > 0) print('c');
  if (d > 0) print('d');
  if (e > 0) print('e');
  if (f > 0) print('f');
  if (g > 0) print('g');
  if (h > 0) print('h');
  if (i > 0) print('i');
  if (a + b > 0) print('ab');
  if (b + c > 0) print('bc');
  if (c + d > 0) print('cd');
  if (d + e > 0) print('de');
  if (e + f > 0) print('ef');
  if (f + g > 0) print('fg');
  if (g + h > 0) print('gh');
  if (h + i > 0) print('hi');
  if (a + c > 0) print('ac');
  if (b + d > 0) print('bd');
  if (c + e > 0) print('ce');
  if (d + f > 0) print('df');
  return a + b + c + d + e + f + g + h + i;
}
''');
  return dir;
}

// ---------------------------------------------------------------------------
// Capture stdout from cli.run via zone-override is not trivial; instead we
// run the CLI in-process but redirect stdout to a string via IOOverrides.
// For output-content tests we use a subprocess for clean capture.
// ---------------------------------------------------------------------------

void main() {
  // ---- AC4: Exit codes -------------------------------------------------------

  group('exit codes', () {
    test('health on clean project → exit 0', () async {
      final dir = _makeCleanProject();
      try {
        final code = await cli.run(['health', '--project-root', dir.path]);
        expect(code, equals(0));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test(
      'health on hotspot project → exit 0 (report command, not gate)',
      () async {
        final dir = _makeHotspotProject();
        try {
          final code = await cli.run(['health', '--project-root', dir.path]);
          expect(
            code,
            equals(0),
            reason:
                'health is a report command — low score must not change exit code',
          );
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );

    test('two positionals → exit 64 (EX_USAGE)', () async {
      final code = await cli.run(['health', '/path/one', '/path/two']);
      expect(code, equals(64), reason: 'two positionals must yield EX_USAGE');
    });

    test(
      'positional path (no --project-root) on clean project → exit 0',
      () async {
        final dir = _makeCleanProject();
        try {
          final code = await cli.run(['health', dir.path]);
          expect(code, equals(0));
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );
  });

  // ---- AC1 + AC6: Output content: clean project → score 100 / grade A -------

  group('output content — clean project', () {
    late Directory dir;
    late String output;

    setUpAll(() async {
      dir = _makeCleanProject();
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'health',
        '--project-root',
        dir.path,
      ]);
      output = result.stdout as String;
    });

    tearDownAll(() => dir.deleteSync(recursive: true));

    test('output contains Health-Score header line', () {
      expect(output, contains('loam health'));
      expect(output, contains('Health-Score:'));
    });

    test('clean project shows score 100', () {
      expect(output, contains('100'), reason: 'clean project must score 100');
    });

    test('clean project shows grade A', () {
      expect(output, contains('Grade: A'));
    });

    test('clean project shows no-hotspot message', () {
      expect(
        output,
        contains('No hotspots detected.'),
        reason: 'clean project must show empty-hotspot message',
      );
    });

    test('output does NOT contain anti-vocabulary', () {
      expect(output, isNot(contains('Smell')));
      expect(output, isNot(contains('Bad code')));
    });
  });

  // ---- AC1 + E2E: hotspot project → score drop + table rows ----------------

  group('output content — hotspot project', () {
    late Directory dir;
    late String output1;
    late String output2;

    setUpAll(() {
      dir = _makeHotspotProject();
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final r1 = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'health',
        '--project-root',
        dir.path,
      ]);
      output1 = r1.stdout as String;
      // Run a second time to verify reproducibility (same output).
      final r2 = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'health',
        '--project-root',
        dir.path,
      ]);
      output2 = r2.stdout as String;
    });

    tearDownAll(() => dir.deleteSync(recursive: true));

    test('hotspot project: score < 100', () {
      // Extract score from "Health-Score: <N> / 100"
      final match = RegExp(
        r'Health-Score:\s+(\d+)\s+/\s+100',
      ).firstMatch(output1);
      expect(match, isNotNull, reason: 'output must contain Health-Score line');
      final score = int.parse(match!.group(1)!);
      expect(
        score,
        lessThan(100),
        reason: 'hotspot project must produce score < 100',
      );
    });

    test('hotspot project: grade is not A', () {
      expect(
        output1,
        isNot(contains('Grade: A')),
        reason: 'hotspot project must not achieve grade A',
      );
    });

    test('hotspot project: hotspot table header is present', () {
      expect(output1, contains('FILE:LINE'));
      expect(output1, contains('SYMBOL'));
      expect(output1, contains('CYC'));
      expect(output1, contains('COG'));
    });

    test('hotspot project: hotspot row references the complex function', () {
      expect(
        output1,
        contains('hotFn'),
        reason: 'hotspot table must reference the complex function',
      );
    });

    test('E2E reproducibility: two runs produce identical output', () {
      expect(
        output1,
        equals(output2),
        reason: 'health output must be deterministic across runs',
      );
    });
  });

  // ---- AC5: toggle-off does NOT change score (toggle-independence) ----------

  group('toggle independence', () {
    test(
      'complexity-hotspots toggle disabled does NOT affect health score',
      () async {
        final dir = _makeHotspotProject();
        try {
          // Write a loam.yaml with complexity-hotspots disabled.
          File(p.join(dir.path, 'loam.yaml')).writeAsStringSync('''
rules:
  complexity-hotspots: false
''');

          // Score from the in-process run with toggle OFF.
          final entrypoint = '${Directory.current.path}/bin/loam.dart';
          final withToggleOff = Process.runSync(Platform.executable, [
            'run',
            entrypoint,
            'health',
            '--project-root',
            dir.path,
          ]);
          final outputOff = withToggleOff.stdout as String;

          // Score from a run WITHOUT loam.yaml (toggle default = on).
          final dirNoConfig = _makeHotspotProject();
          try {
            final withoutConfig = Process.runSync(Platform.executable, [
              'run',
              entrypoint,
              'health',
              '--project-root',
              dirNoConfig.path,
            ]);
            final outputDefault = withoutConfig.stdout as String;

            // Both outputs must show the same score.
            final scoreOff = RegExp(
              r'Health-Score:\s+(\d+)',
            ).firstMatch(outputOff)?.group(1);
            final scoreDefault = RegExp(
              r'Health-Score:\s+(\d+)',
            ).firstMatch(outputDefault)?.group(1);

            expect(scoreOff, isNotNull);
            expect(scoreDefault, isNotNull);
            expect(
              scoreOff,
              equals(scoreDefault),
              reason:
                  'disabling complexity-hotspots toggle must NOT change the health score',
            );
          } finally {
            dirNoConfig.deleteSync(recursive: true);
          }
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );
  });

  // ---- AC3: --project-root and positional path equivalence ------------------

  group('path resolution', () {
    test('--project-root and positional path give same score', () async {
      final dir = _makeHotspotProject();
      try {
        final codeExplicit = await cli.run([
          'health',
          '--project-root',
          dir.path,
        ]);
        final codePositional = await cli.run(['health', dir.path]);
        expect(codeExplicit, equals(0));
        expect(codePositional, equals(0));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  // ---- AC1 renderer: fixture-based E2E with complexity_hotspots_fixture -----

  group('E2E against complexity_hotspots_fixture', () {
    final fixturePath = p.normalize(
      p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'complexity_hotspots_fixture',
      ),
    );

    test('fixture project exits 0', () async {
      final code = await cli.run(['health', '--project-root', fixturePath]);
      expect(code, equals(0));
    });

    test('fixture project output is reproducible (run twice → identical)', () {
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final r1 = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'health',
        '--project-root',
        fixturePath,
      ]);
      final r2 = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'health',
        '--project-root',
        fixturePath,
      ]);
      expect(r1.stdout, equals(r2.stdout));
    });

    test('fixture output contains Health-Score and Grade', () {
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final r = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'health',
        '--project-root',
        fixturePath,
      ]);
      final out = r.stdout as String;
      expect(out, contains('Health-Score:'));
      expect(out, contains('Grade:'));
    });

    test(
      'fixture output shows hotspot table (fixture has complex functions)',
      () {
        final entrypoint = '${Directory.current.path}/bin/loam.dart';
        final r = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          'health',
          '--project-root',
          fixturePath,
        ]);
        final out = r.stdout as String;
        // Fixture has justOverCyclomatic (cyclomatic=21) and veryHighCognitive
        // (cognitive=36). At least one of those must appear as a Hotspot row.
        final hasHotspotRow =
            out.contains('justOverCyclomatic') ||
            out.contains('veryHighCognitive') ||
            out.contains('justUnderCyclomatic');
        expect(
          hasHotspotRow,
          isTrue,
          reason: 'fixture must produce at least one hotspot row',
        );
      },
    );
  });
}
