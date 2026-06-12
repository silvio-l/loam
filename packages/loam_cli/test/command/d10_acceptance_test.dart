@TestOn('vm')
library;

/// D10 acceptance sequence — end-to-end CLI test.
///
/// Walks the complete D10 proof-of-both-operating-modes via the real
/// `cli.run([...])` entrypoint against a temporary fixture:
///
///   1. scan      → exit 1 (findings present in fixture)
///   2. baseline --write → exit 0 (baseline.json created)
///   3. gate (ratchet)  → exit 0 (baseline frozen, no NEW findings)
///   4. add new unused export → gate (ratchet) → exit 1 (new finding)
///   5. remove new export    → gate (ratchet) → exit 0
///   6. gate --absolute on fixture with findings → exit 1 (no baseline needed)
///   7. gate --absolute on clean fixture         → exit 0 (no baseline needed)
///
/// This test is part of the gate and exercises the single production path
/// (AnalysisRunner → GateEngine / BaselineEngine, per ADR-0003 / D10).
///
/// Timeout: each step runs the Dart analyser; allow 4 minutes total.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;

// ---------------------------------------------------------------------------
// Fixture helpers (reuse pattern from gate_command_test.dart / scan_command_test.dart)
// ---------------------------------------------------------------------------

/// Creates a minimal Dart package with ONE unused public class (→ finding).
///
/// The class lives in its own file and is never imported — loam's
/// unused-public-exports rule detects it as a public top-level symbol with
/// zero references.
Directory _makeProjectWithFinding() {
  final dir = Directory.systemTemp.createTempSync('loam_d10_test_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: d10_test_pkg
publish_to: none
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  // An entry-point file that doesn't re-export the unused class:
  File(p.join(dir.path, 'lib', 'lib.dart')).writeAsStringSync('// empty\n');
  // Unused public class:
  File(p.join(dir.path, 'lib', 'unused_initial.dart')).writeAsStringSync('''
/// Public class that is never referenced anywhere.
class InitialUnusedClass {}
''');
  return dir;
}

/// Creates a minimal clean Dart package (no findings).
Directory _makeCleanProject() {
  final dir = Directory.systemTemp.createTempSync('loam_d10_clean_test_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: d10_clean_pkg
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  File(p.join(dir.path, 'lib', 'lib.dart')).writeAsStringSync('// empty\n');
  return dir;
}

/// Adds a NEW unused public class to lib/ to trigger a gate regression.
void _addNewUnusedExport(Directory dir) {
  File(p.join(dir.path, 'lib', 'new_unused.dart')).writeAsStringSync('''
/// A NEW public class — added after baseline was frozen.
/// gate (ratchet) must report this as a new finding.
class NewUnusedClass {}
''');
}

/// Removes the NEW unused public class (reverts to baseline state).
void _removeNewUnusedExport(Directory dir) {
  final file = File(p.join(dir.path, 'lib', 'new_unused.dart'));
  if (file.existsSync()) file.deleteSync();
}

// ---------------------------------------------------------------------------
// D10 acceptance test
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // D10 full sequence (steps 1–5: ratchet mode)
  // -------------------------------------------------------------------------
  group('D10 full acceptance sequence', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _makeProjectWithFinding();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
      'step 1 — scan: exit 1 when findings present',
      () async {
        final code = await cli.run(['scan', '--project-root', tempDir.path]);
        expect(
          code,
          equals(1),
          reason: 'scan must exit 1 when findings are present',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'step 2 — baseline --write: exit 0, baseline.json created',
      () async {
        final code = await cli.run([
          'baseline',
          '--write',
          '--project-root',
          tempDir.path,
        ]);
        expect(code, equals(0), reason: 'baseline --write must succeed');
        expect(
          File(p.join(tempDir.path, 'baseline.json')).existsSync(),
          isTrue,
          reason: 'baseline.json must be created',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'step 3 — gate (ratchet): exit 0 after baseline freezes existing finding',
      () async {
        // Write baseline first.
        await cli.run(['baseline', '--write', '--project-root', tempDir.path]);

        // Gate must be green: the one finding is frozen in baseline → 0 NEW.
        final code = await cli.run(['gate', '--project-root', tempDir.path]);
        expect(
          code,
          equals(0),
          reason:
              'gate (ratchet) must exit 0 when baseline covers all findings',
        );
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'step 4 — gate (ratchet): exit 1 after NEW unused export added',
      () async {
        // Write baseline on original state (1 finding frozen).
        await cli.run(['baseline', '--write', '--project-root', tempDir.path]);

        // Add a new, additional unused export.
        _addNewUnusedExport(tempDir);

        // Gate must be red: 1 NEW finding.
        final code = await cli.run(['gate', '--project-root', tempDir.path]);
        expect(
          code,
          equals(1),
          reason: 'gate must exit 1 after introducing a new unused export',
        );
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );

    test(
      'step 5 — gate (ratchet): exit 0 after NEW export removed',
      () async {
        // Write baseline, add new export, then remove it again.
        await cli.run(['baseline', '--write', '--project-root', tempDir.path]);
        _addNewUnusedExport(tempDir);
        _removeNewUnusedExport(tempDir);

        // Gate must be green again.
        final code = await cli.run(['gate', '--project-root', tempDir.path]);
        expect(
          code,
          equals(0),
          reason: 'gate must exit 0 after removing the new unused export',
        );
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  });

  // -------------------------------------------------------------------------
  // D10 steps 6–7: gate --absolute mode (no baseline required)
  // -------------------------------------------------------------------------
  group('D10 gate --absolute (no baseline)', () {
    test(
      'step 6 — gate --absolute: exit 1 when findings present (no baseline needed)',
      () async {
        final dir = _makeProjectWithFinding();
        addTearDown(() => dir.deleteSync(recursive: true));

        // No baseline.json written — absolute mode must not need one.
        final code = await cli.run([
          'gate',
          '--absolute',
          '--project-root',
          dir.path,
        ]);
        expect(
          code,
          equals(1),
          reason:
              'gate --absolute must exit 1 when findings > threshold (0), '
              'without requiring a baseline',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'step 7 — gate --absolute: exit 0 on clean project (no baseline needed)',
      () async {
        final dir = _makeCleanProject();
        addTearDown(() => dir.deleteSync(recursive: true));

        // No baseline.json written — absolute mode must not need one.
        final code = await cli.run([
          'gate',
          '--absolute',
          '--project-root',
          dir.path,
        ]);
        expect(
          code,
          equals(0),
          reason:
              'gate --absolute must exit 0 on clean project, '
              'without requiring a baseline',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
