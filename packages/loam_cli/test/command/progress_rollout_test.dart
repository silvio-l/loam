@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Regression suite for the `--no-progress` / `LOAM_NO_PROGRESS` rollout onto
/// `gate`, `baseline`, `slop`, `a11y` and `health` (issue
/// `02-progress-rollout-commands`).
///
/// The live progress bar itself only renders on a real TTY, which a spawned
/// `Process.run` never attaches — so `showProgress` resolves to `false` in
/// every scenario exercised here, exactly as it did before the rollout. What
/// this suite actually guards against:
///   - the `--no-progress` flag / `LOAM_NO_PROGRESS` env var must be *accepted*
///     by all five commands without changing their usage-parsing outcome,
///   - stdout must stay byte-identical regardless of the flag/env (AC:
///     structured output never carries progress noise — the seam only ever
///     writes to stderr, and even that only when `showProgress` is true),
///   - exit codes (incl. gate's ratchet/absolute gating and health's fixed
///     exit 0) must be unaffected by wiring the [ProgressSink] through.
///
/// Whether the bar itself actually renders on a real TTY is covered by the
/// pure-function tests in `test/progress/should_show_progress_test.dart` plus
/// the renderer unit tests in `test/progress/`.
void main() {
  final entrypoint = p.join(Directory.current.path, 'bin', 'loam.dart');

  final unusedExportsFixture = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    ),
  );
  final slopFixture = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'slop_unjustified_ignore_fixture',
    ),
  );
  final a11yFixture = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'a11y_image_label_fixture',
    ),
  );

  ProcessResult runCli(
    List<String> args, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) {
    return Process.runSync(
      Platform.executable,
      ['run', entrypoint, ...args],
      environment: environment,
      workingDirectory: workingDirectory,
    );
  }

  /// Creates a clean, finding-free Dart project (no baseline.json).
  Directory makeCleanProject(String prefix) {
    final dir = Directory.systemTemp.createTempSync(prefix);
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: ${prefix}_pkg
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
    Directory(p.join(dir.path, 'lib')).createSync();
    File(
      p.join(dir.path, 'lib', 'clean.dart'),
    ).writeAsStringSync('// intentionally empty\n');
    return dir;
  }

  // ---------------------------------------------------------------------------
  // Shared assertion: stdout must be byte-identical, and exit code identical,
  // across "default" / "--no-progress" / "LOAM_NO_PROGRESS=1" invocations.
  // ---------------------------------------------------------------------------
  void expectProgressFlagsAreStdoutNeutral(List<String> args) {
    final baseline = runCli(args);
    final withFlag = runCli([...args, '--no-progress']);
    final withEnv = runCli(args, environment: {'LOAM_NO_PROGRESS': '1'});

    expect(
      withFlag.stdout,
      equals(baseline.stdout),
      reason: '--no-progress must not change stdout',
    );
    expect(
      withEnv.stdout,
      equals(baseline.stdout),
      reason: 'LOAM_NO_PROGRESS must not change stdout',
    );
    expect(
      withFlag.exitCode,
      equals(baseline.exitCode),
      reason: '--no-progress must not change the exit code',
    );
    expect(
      withEnv.exitCode,
      equals(baseline.exitCode),
      reason: 'LOAM_NO_PROGRESS must not change the exit code',
    );
  }

  group('gate — progress flag neutrality', () {
    test('gate --absolute on a project with findings', () {
      expectProgressFlagsAreStdoutNeutral([
        'gate',
        '--absolute',
        '--project-root',
        unusedExportsFixture,
      ]);
    });

    test('gate --absolute on a clean project → exit 0', () {
      final dir = makeCleanProject('loam_progress_gate_clean_');
      try {
        final r = runCli(['gate', '--absolute', '--project-root', dir.path]);
        expect(r.exitCode, equals(0));
        expectProgressFlagsAreStdoutNeutral([
          'gate',
          '--absolute',
          '--project-root',
          dir.path,
        ]);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test(
      'CI env auto-disables progress without changing exit code / stdout',
      () {
        final dir = makeCleanProject('loam_progress_gate_ci_');
        try {
          final args = ['gate', '--absolute', '--project-root', dir.path];
          final withoutCi = runCli(args);
          final withCi = runCli(args, environment: {'CI': 'true'});
          expect(withCi.exitCode, equals(withoutCi.exitCode));
          expect(withCi.stdout, equals(withoutCi.stdout));
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
    );
  });

  group('baseline — progress flag neutrality', () {
    test('baseline --write on a project with findings', () {
      final dir = Directory.systemTemp.createTempSync(
        'loam_progress_baseline_',
      );
      try {
        File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: baseline_progress_pkg
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
        Directory(p.join(dir.path, 'lib')).createSync();
        File(p.join(dir.path, 'lib', 'unused.dart')).writeAsStringSync('''
/// Never referenced anywhere.
class NeverUsed {}
''');
        expectProgressFlagsAreStdoutNeutral([
          'baseline',
          '--write',
          '--project-root',
          dir.path,
        ]);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('slop — progress flag neutrality', () {
    test('slop on a fixture with unjustified ignores → exit 1', () {
      final r = runCli(['slop', '--project-root', slopFixture]);
      expect(r.exitCode, equals(1));
      expectProgressFlagsAreStdoutNeutral([
        'slop',
        '--project-root',
        slopFixture,
      ]);
    });
  });

  group('a11y — progress flag neutrality', () {
    test('a11y on a fixture with a missing image label → exit 1', () {
      final r = runCli(['a11y', '--project-root', a11yFixture]);
      expect(r.exitCode, equals(1));
      expectProgressFlagsAreStdoutNeutral([
        'a11y',
        '--project-root',
        a11yFixture,
      ]);
    });
  });

  group('health — progress flag neutrality', () {
    test('health on a clean project → exit 0, stdout unaffected', () {
      final dir = makeCleanProject('loam_progress_health_');
      try {
        final r = runCli(['health', '--project-root', dir.path]);
        expect(r.exitCode, equals(0));
        expectProgressFlagsAreStdoutNeutral([
          'health',
          '--project-root',
          dir.path,
        ]);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
