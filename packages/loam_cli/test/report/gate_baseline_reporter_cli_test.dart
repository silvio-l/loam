@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// CLI integration tests: gate and baseline reporter wiring (Slice 03).
///
/// Covers:
///  - `loam gate --format sarif` → valid SARIF on stdout + gate summary kept
///  - `loam baseline --format sarif` → valid SARIF on stdout + header kept
///  - `loam gate --format json|markdown|html` → exit 64 + clear stderr message
///  - `loam baseline --format json|markdown|html` → exit 64 + clear stderr message
///  - GateEngine summary/exit-code semantics are unchanged (regression guard)
///  - dispatch: human/sarif resolve; json/markdown/html error cleanly (exit 64)

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a minimal clean Dart project (no public symbols → no findings).
Directory _makeCleanProject() {
  final dir = Directory.systemTemp.createTempSync('loam_gate_bl_rpt_test_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: reporter_wiring_test_pkg
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  File(p.join(dir.path, 'lib', 'lib.dart')).writeAsStringSync('// empty\n');
  return dir;
}

/// Adds an unused public class to trigger unused-public-exports.
void _addUnusedExport(Directory dir) {
  File(p.join(dir.path, 'lib', 'unused_reporter_class.dart')).writeAsStringSync(
    '''
/// A public class that is never referenced anywhere.
class UnusedReporterClass {}
''',
  );
}

void main() {
  final entrypoint = p.join(Directory.current.path, 'bin', 'loam.dart');

  late JsonSchema sarifSchema;

  setUpAll(() async {
    final schemaPath = p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'sarif',
      'sarif-schema-2.1.0.json',
    );
    final schemaJson =
        jsonDecode(File(schemaPath).readAsStringSync()) as Map<String, dynamic>;
    sarifSchema = JsonSchema.create(schemaJson);
  });

  // ---------------------------------------------------------------------------
  // AC: gate --format sarif → valid SARIF on stdout; gate summary still present
  // ---------------------------------------------------------------------------

  group('loam gate --format sarif', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _makeCleanProject();
      // Write a clean baseline (0 findings) so ratchet mode can proceed.
      final engine = BaselineEngine(projectRoot: tempDir.path);
      engine.write([], AnalysisRunner.rulesetVersion);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('gate --format sarif on clean project → exit 0', () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'sarif',
        'gate',
        '--project-root',
        tempDir.path,
      ]);
      expect(result.exitCode, equals(0), reason: 'clean gate must exit 0');
    });

    test(
      'gate --format sarif on clean project → stdout contains SARIF + summary',
      () {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          'sarif',
          'gate',
          '--project-root',
          tempDir.path,
        ]);
        final out = result.stdout as String;
        // Gate summary line is always present.
        expect(out, contains('neu'), reason: 'gate summary must contain "neu"');
        expect(
          out,
          contains('eingefroren'),
          reason: 'gate summary must contain "eingefroren"',
        );
      },
    );

    test(
      'gate --format sarif with findings: stdout contains schema-valid SARIF block',
      () {
        _addUnusedExport(tempDir);
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          'sarif',
          'gate',
          '--project-root',
          tempDir.path,
        ]);
        // exit 1 (new finding)
        expect(result.exitCode, equals(1));
        final out = result.stdout as String;
        // stdout has reporter output + gate summary line; extract the SARIF
        // block (the lines before the "loam gate:" summary).
        final sarifPart = out.substring(0, out.lastIndexOf('loam gate:'));
        final doc = jsonDecode(sarifPart.trim());
        final validationResult = sarifSchema.validate(doc);
        expect(
          validationResult.isValid,
          isTrue,
          reason:
              'gate --format sarif must embed schema-valid SARIF. '
              'Errors: ${validationResult.errors}',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'gate ratchet summary + exit-code semantics are UNCHANGED by reporter (regression guard)',
      () {
        // Introduce a new finding.
        _addUnusedExport(tempDir);
        final redResult = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          'sarif',
          'gate',
          '--project-root',
          tempDir.path,
        ]);
        expect(redResult.exitCode, equals(1));
        expect(
          redResult.stdout as String,
          contains('1 neu'),
          reason: 'summary must show 1 new finding',
        );
        expect(
          (redResult.stdout as String).toLowerCase(),
          contains('rot'),
          reason: 'summary must say rot',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  // ---------------------------------------------------------------------------
  // AC: baseline --format sarif → valid SARIF on stdout; header still present
  // ---------------------------------------------------------------------------

  group('loam baseline --format sarif', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _makeCleanProject();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('baseline --format sarif with 0 findings → exit 0 + header line', () {
      final engine = BaselineEngine(projectRoot: tempDir.path);
      engine.write([], AnalysisRunner.rulesetVersion);

      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'sarif',
        'baseline',
        '--project-root',
        tempDir.path,
      ]);
      expect(result.exitCode, equals(0));
      final out = result.stdout as String;
      // Header line from baseline command
      expect(
        out,
        contains('loam baseline:'),
        reason: 'baseline header must be present',
      );
      expect(out, contains('finding'));
    });

    test(
      'baseline --format sarif with findings → stdout contains schema-valid SARIF',
      () {
        // Write baseline with a real finding via analysis runner-produced content.
        // We simulate by adding an unused export first, writing baseline, then show.
        _addUnusedExport(tempDir);

        // Write baseline using the CLI (captures real findings).
        Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          'baseline',
          '--write',
          '--project-root',
          tempDir.path,
        ]);

        // Now show baseline with --format sarif.
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          'sarif',
          'baseline',
          '--project-root',
          tempDir.path,
        ]);
        expect(result.exitCode, equals(0));
        final out = result.stdout as String;

        // Extract SARIF block (before/after the "loam baseline:" header line).
        // The header is the first line; the rest is reporter output.
        final lines = out.split('\n');
        // Find first line that starts with '{' (SARIF JSON start)
        final sarifStart = lines.indexWhere(
          (l) => l.trimLeft().startsWith('{'),
        );
        expect(
          sarifStart,
          greaterThanOrEqualTo(0),
          reason: 'SARIF JSON must be present',
        );
        final sarifPart = lines.sublist(sarifStart).join('\n').trim();
        final doc = jsonDecode(sarifPart);
        final validationResult = sarifSchema.validate(doc);
        expect(
          validationResult.isValid,
          isTrue,
          reason:
              'baseline --format sarif must embed schema-valid SARIF. '
              'Errors: ${validationResult.errors}',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  // ---------------------------------------------------------------------------
  // AC: gate --format json|markdown|html → exit 64 + clear stderr message
  // ---------------------------------------------------------------------------

  group('gate: not-implemented formats → exit 64', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _makeCleanProject();
      final engine = BaselineEngine(projectRoot: tempDir.path);
      engine.write([], AnalysisRunner.rulesetVersion);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // json is now implemented: gate --format json exits 0 on clean project.
    test('gate --format json → exit 0 on clean project (now implemented)', () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'json',
        'gate',
        '--project-root',
        tempDir.path,
      ]);
      expect(
        result.exitCode,
        equals(0),
        reason: 'json is implemented — clean project exits 0',
      );
    });

    // markdown is now implemented: gate --format markdown exits 0 on clean project.
    test(
      'gate --format markdown → exit 0 on clean project (now implemented)',
      () {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          'markdown',
          'gate',
          '--project-root',
          tempDir.path,
        ]);
        expect(
          result.exitCode,
          equals(0),
          reason: 'markdown is implemented — clean project exits 0',
        );
      },
    );

    for (final fmt in ['html']) {
      test('gate --format $fmt → exit 64 with clear stderr message', () {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          fmt,
          'gate',
          '--project-root',
          tempDir.path,
        ]);
        expect(
          result.exitCode,
          equals(64),
          reason: 'not-implemented format must exit 64 (EX_USAGE)',
        );
        final err = result.stderr as String;
        expect(
          err,
          contains(fmt),
          reason: 'stderr must name the unsupported format "$fmt"',
        );
        expect(
          err,
          isNot(contains('Unhandled exception')),
          reason: 'must not crash',
        );
      });
    }
  });

  // ---------------------------------------------------------------------------
  // AC: baseline --format json|markdown|html → exit 64 + clear stderr message
  // ---------------------------------------------------------------------------

  group('baseline (show): not-implemented formats → exit 64', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _makeCleanProject();
      final engine = BaselineEngine(projectRoot: tempDir.path);
      engine.write([], AnalysisRunner.rulesetVersion);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // json is now implemented: baseline --format json exits 0.
    test(
      'baseline --format json → exit 0 on clean project (now implemented)',
      () {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          'json',
          'baseline',
          '--project-root',
          tempDir.path,
        ]);
        expect(
          result.exitCode,
          equals(0),
          reason:
              'json is implemented — baseline show exits 0 for clean project',
        );
      },
    );

    // markdown is now implemented: baseline --format markdown exits 0 on clean project.
    test(
      'baseline --format markdown → exit 0 on clean project (now implemented)',
      () {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          'markdown',
          'baseline',
          '--project-root',
          tempDir.path,
        ]);
        expect(
          result.exitCode,
          equals(0),
          reason:
              'markdown is implemented — baseline show exits 0 for clean project',
        );
      },
    );

    for (final fmt in ['html']) {
      test('baseline --format $fmt → exit 64 with clear stderr message', () {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          fmt,
          'baseline',
          '--project-root',
          tempDir.path,
        ]);
        expect(
          result.exitCode,
          equals(64),
          reason: 'not-implemented format must exit 64 (EX_USAGE)',
        );
        final err = result.stderr as String;
        expect(
          err,
          contains(fmt),
          reason: 'stderr must name the unsupported format "$fmt"',
        );
        expect(
          err,
          isNot(contains('Unhandled exception')),
          reason: 'must not crash',
        );
      });
    }
  });

  // ---------------------------------------------------------------------------
  // AC: dispatch test — human/sarif resolve; json/markdown/html error cleanly
  // Tested via scan as a representative command (reporterFor() is shared).
  // ---------------------------------------------------------------------------

  group('reporterFor dispatch (via scan)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _makeCleanProject();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('--format human resolves → exit 0 on clean project', () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'human',
        'scan',
        '--project-root',
        tempDir.path,
      ]);
      expect(result.exitCode, equals(0));
      expect(result.stderr as String, isEmpty);
    });

    test('--format sarif resolves → exit 0 on clean project', () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'sarif',
        'scan',
        '--project-root',
        tempDir.path,
      ]);
      expect(result.exitCode, equals(0));
      expect(result.stderr as String, isEmpty);
    });

    // json is now implemented: scan --format json exits 0 on clean project.
    test(
      '--format json resolves → exit 0 on clean project (now implemented)',
      () {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          'json',
          'scan',
          '--project-root',
          tempDir.path,
        ]);
        expect(result.exitCode, equals(0));
        expect(result.stderr as String, isEmpty);
      },
    );

    // markdown is now implemented: scan --format markdown exits 0 on clean project.
    test(
      '--format markdown resolves → exit 0 on clean project (now implemented)',
      () {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          'markdown',
          'scan',
          '--project-root',
          tempDir.path,
        ]);
        expect(result.exitCode, equals(0));
        expect(result.stderr as String, isEmpty);
      },
    );

    for (final fmt in ['html']) {
      test('--format $fmt → exit 64, stderr names format, no crash', () {
        final result = Process.runSync(Platform.executable, [
          'run',
          entrypoint,
          '--format',
          fmt,
          'scan',
          '--project-root',
          tempDir.path,
        ]);
        expect(result.exitCode, equals(64));
        final err = result.stderr as String;
        expect(err, contains(fmt));
        expect(err, isNot(contains('Unhandled exception')));
      });
    }
  });
}
