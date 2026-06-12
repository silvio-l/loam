@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a minimal clean Dart project (no public symbols → no findings).
Directory _makeCleanProject() {
  final dir = Directory.systemTemp.createTempSync('loam_gate_cmd_test_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: gate_test_pkg
publish_to: none
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  // A library with no exports → no findings.
  File(p.join(dir.path, 'lib', 'lib.dart')).writeAsStringSync('// empty\n');
  return dir;
}

/// Adds an unused public class to lib/ so that `unused-public-exports` fires.
///
/// The class lives in its own file and is never imported anywhere — the rule
/// detects it as a public top-level symbol with zero references.
void _addUnusedExport(Directory dir) {
  File(p.join(dir.path, 'lib', 'unused_gate_class.dart')).writeAsStringSync('''
/// A public class that is never referenced anywhere.
/// Added by the gate test to trigger unused-public-exports.
class UnusedGateClass {}
''');
}

/// Removes the unused public class (reverts to clean state).
void _removeUnusedExport(Directory dir) {
  final file = File(p.join(dir.path, 'lib', 'unused_gate_class.dart'));
  if (file.existsSync()) file.deleteSync();
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = _makeCleanProject();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // AC5: Missing baseline.json → clear error with hint (no crash)
  // ---------------------------------------------------------------------------

  test(
    'gate without baseline.json → exit 1 with clear error on stderr',
    () async {
      // Use subprocess to capture stderr.
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'gate',
        '--project-root',
        tempDir.path,
      ]);

      expect(
        result.exitCode,
        equals(1),
        reason: 'must exit 1 when no baseline',
      );
      final combined = '${result.stdout}${result.stderr}';
      expect(
        combined.toLowerCase(),
        anyOf(contains('missing'), contains('baseline'), contains('--write')),
        reason: 'must mention missing baseline or hint at --write',
      );
      // Must NOT crash with a Dart stack trace.
      expect(
        combined,
        isNot(contains('Unhandled exception')),
        reason: 'must not produce an unhandled exception',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // AC3 + AC6: D10 sub-sequence
  //   baseline --write → add unused export → gate Exit 1 → remove → gate Exit 0
  // ---------------------------------------------------------------------------

  test(
    'D10 sub-sequence: baseline --write → new finding → gate Exit 1 → fix → gate Exit 0',
    () async {
      // Step 1: write baseline on the clean project (0 findings).
      final writeCode = await cli.run([
        'baseline',
        '--write',
        '--project-root',
        tempDir.path,
      ]);
      expect(writeCode, equals(0), reason: 'baseline --write must succeed');

      // Step 2: introduce a new unused export.
      _addUnusedExport(tempDir);

      // Step 3: gate must now exit 1 (1 new finding).
      final gateRedCode = await cli.run([
        'gate',
        '--project-root',
        tempDir.path,
      ]);
      expect(
        gateRedCode,
        equals(1),
        reason: 'gate must be red after adding unused export',
      );

      // Step 4: remove the unused export.
      _removeUnusedExport(tempDir);

      // Step 5: gate must exit 0 again (no new findings).
      final gateGreenCode = await cli.run([
        'gate',
        '--project-root',
        tempDir.path,
      ]);
      expect(
        gateGreenCode,
        equals(0),
        reason: 'gate must be green after removing unused export',
      );
    },
    // The test runs the Dart analyser twice — allow enough time.
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // ---------------------------------------------------------------------------
  // AC3: Summary line on stdout (neu/eingefroren/gefixt)
  // ---------------------------------------------------------------------------

  test(
    'gate stdout contains summary line with neu/eingefroren/gefixt',
    () async {
      // Write a clean baseline first.
      await cli.run(['baseline', '--write', '--project-root', tempDir.path]);

      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'gate',
        '--project-root',
        tempDir.path,
      ]);

      final out = result.stdout as String;
      expect(out, contains('neu'), reason: 'summary must contain "neu"');
      expect(
        out,
        contains('eingefroren'),
        reason: 'summary must contain "eingefroren"',
      );
      expect(out, contains('gefixt'), reason: 'summary must contain "gefixt"');
    },
  );

  // ---------------------------------------------------------------------------
  // AC2 + AC3: loam gate --absolute without baseline.json
  // ---------------------------------------------------------------------------

  test(
    'gate --absolute with findings → exit 1 (no baseline required)',
    () async {
      // No baseline.json is written — absolute mode must not need one.
      _addUnusedExport(tempDir);

      final exitCode = await cli.run([
        'gate',
        '--absolute',
        '--project-root',
        tempDir.path,
      ]);

      expect(
        exitCode,
        equals(1),
        reason: 'gate --absolute must exit 1 when findings > threshold (0)',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'gate --absolute on clean project → exit 0 (no baseline required)',
    () async {
      // No baseline.json is written — absolute mode must not need one.
      final exitCode = await cli.run([
        'gate',
        '--absolute',
        '--project-root',
        tempDir.path,
      ]);

      expect(
        exitCode,
        equals(0),
        reason: 'gate --absolute must exit 0 when no findings',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'gate --absolute stdout contains finding count and grün/rot',
    () async {
      final entrypoint = '${Directory.current.path}/bin/loam.dart';

      // Run on clean project → grün.
      final cleanResult = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'gate',
        '--absolute',
        '--project-root',
        tempDir.path,
      ]);
      expect(
        (cleanResult.stdout as String).toLowerCase(),
        contains('grün'),
        reason: 'clean absolute gate must show grün',
      );

      // Add unused export → rot.
      _addUnusedExport(tempDir);
      final dirtyResult = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'gate',
        '--absolute',
        '--project-root',
        tempDir.path,
      ]);
      expect(
        (dirtyResult.stdout as String).toLowerCase(),
        contains('rot'),
        reason: 'dirty absolute gate must show rot',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // ---------------------------------------------------------------------------
  // AC4: rulesetVersion mismatch → stderr warning, diff continues (no fail)
  // ---------------------------------------------------------------------------

  test(
    'rulesetVersion mismatch → stderr warning, gate continues normally',
    () async {
      // Write a baseline with a fake rulesetVersion that doesn't match current.
      final entrypoint = '${Directory.current.path}/bin/loam.dart';

      // Write the baseline (correct rulesetVersion).
      await cli.run(['baseline', '--write', '--project-root', tempDir.path]);

      // Overwrite the baseline.json with a stale rulesetVersion.
      final baselineFile = File(p.join(tempDir.path, 'baseline.json'));
      final content = baselineFile.readAsStringSync();
      baselineFile.writeAsStringSync(
        content.replaceFirst(
          RegExp(r'"rulesetVersion":\s*"[^"]*"'),
          '"rulesetVersion": "ruleset@stale000"',
        ),
      );

      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'gate',
        '--project-root',
        tempDir.path,
      ]);

      // Should still pass (clean project, no new findings).
      expect(
        result.exitCode,
        equals(0),
        reason:
            'rulesetVersion mismatch must not cause a fail on clean project',
      );
      // Warning must appear on stderr.
      final combined = '${result.stdout}${result.stderr}';
      expect(
        combined.toLowerCase(),
        anyOf(
          contains('warn'),
          contains('mismatch'),
          contains('differs'),
          contains('stale'),
        ),
        reason: 'must emit a warning about rulesetVersion mismatch on stderr',
      );
    },
  );
}
