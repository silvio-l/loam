@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_runner.dart';
import '../support/shared_store.dart';

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

int? _score(String out) {
  final m = RegExp(r'Health-Score:\s+(\d+)').firstMatch(out);
  return m == null ? null : int.parse(m.group(1)!);
}

void main() {
  useSharedAnalyzerStore();

  late Directory clean;
  late Directory hotspot;
  late CliResult cleanRun;
  late CliResult hotspotRun;

  // One analysis per project for the whole file.
  setUpAll(() async {
    clean = _makeCleanProject();
    hotspot = _makeHotspotProject();
    cleanRun = await runCli(['health', '--project-root', clean.path]);
    hotspotRun = await runCli(['health', '--project-root', hotspot.path]);
  });

  tearDownAll(() {
    clean.deleteSync(recursive: true);
    hotspot.deleteSync(recursive: true);
  });

  group('exit codes', () {
    test('health is a report command: exit 0 even with hotspots', () {
      expect(cleanRun.exitCode, 0);
      expect(hotspotRun.exitCode, 0);
    });

    test('two positionals → exit 64 (EX_USAGE)', () async {
      final r = await runCli(['health', '/path/one', '/path/two']);
      expect(r.exitCode, 64);
    });
  });

  group('score', () {
    test('clean project scores 100 / grade A without hotspots', () {
      expect(_score(cleanRun.stdout), 100);
      expect(cleanRun.stdout, contains('Grade: A'));
    });

    test('hotspot project scores below 100 and names the complex function', () {
      expect(_score(hotspotRun.stdout), lessThan(100));
      expect(hotspotRun.stdout, isNot(contains('Grade: A')));
      expect(hotspotRun.stdout, contains('hotFn'));
    });

    test('same input produces identical output (reproducibility)', () async {
      final again = await runCli(['health', '--project-root', hotspot.path]);
      expect(again.stdout, hotspotRun.stdout);
    });

    test('--project-root and positional path give the same score', () async {
      final positional = await runCli(['health', hotspot.path]);
      expect(positional.exitCode, 0);
      expect(_score(positional.stdout), _score(hotspotRun.stdout));
    });

    test('complexity-hotspots toggle does not change the score', () async {
      final dir = _makeHotspotProject();
      try {
        File(p.join(dir.path, 'loam.yaml')).writeAsStringSync('''
rules:
  complexity-hotspots: false
''');
        final off = await runCli(['health', '--project-root', dir.path]);
        expect(_score(off.stdout), isNotNull);
        expect(_score(off.stdout), _score(hotspotRun.stdout));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
