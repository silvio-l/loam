@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;
import '../support/shared_store.dart';

void main() {
  useSharedAnalyzerStore();

  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    ),
  );

  // ---------------------------------------------------------------------------
  // AC3: loam scan emits a provisional minimal output (finding list + summary)
  // AC4: Exit 1 when findings present, exit 0 when clean
  // ---------------------------------------------------------------------------

  test('scan with findings fixture → exit 1', () async {
    final code = await cli.run(['scan', '--project-root', fixturePath]);
    expect(code, equals(1), reason: 'should exit 1 when findings are present');
  });

  // ---------------------------------------------------------------------------
  // AC4: Exit 0 on a clean (no-findings) project
  // We use a temporary empty Dart project for this.
  // ---------------------------------------------------------------------------

  test('scan on empty project (no findings) → exit 0', () async {
    final tempDir = Directory.systemTemp.createTempSync('loam_scan_test_');
    try {
      // Minimal Dart package: pubspec.yaml + empty lib/src/clean.dart
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: clean_project
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
      Directory(p.join(tempDir.path, 'lib')).createSync();
      File(
        p.join(tempDir.path, 'lib', 'clean.dart'),
      ).writeAsStringSync('// empty library\n');

      final code = await cli.run(['scan', '--project-root', tempDir.path]);
      expect(code, equals(0), reason: 'should exit 0 when no findings');
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // TargetRootResolver integration (Issue 01):
  //   - positional path is used instead of CWD
  //   - two positionals → exit 64 on stderr
  // ---------------------------------------------------------------------------

  group('positional project path (TargetRootResolver)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('loam_scan_pos_test_');
      // Minimal Dart package: pubspec.yaml + empty lib/clean.dart
      File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: clean_project
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
      Directory(p.join(tempDir.path, 'lib')).createSync();
      File(
        p.join(tempDir.path, 'lib', 'clean.dart'),
      ).writeAsStringSync('// empty library\n');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test(
      'loam scan <path> analyses <path> (not CWD) → exit 0 for clean project',
      () async {
        // Pass path as positional (no --project-root flag).
        final code = await cli.run(['scan', tempDir.path]);
        expect(
          code,
          equals(0),
          reason: 'positional path must be used: clean temp project → exit 0',
        );
      },
    );

    test(
      'loam scan <path> with findings fixture → exit 1 via positional',
      () async {
        final code = await cli.run(['scan', fixturePath]);
        expect(
          code,
          equals(1),
          reason:
              'positional path must point at fixture: findings present → exit 1',
        );
      },
    );

    test('two positionals → exit 64 (EX_USAGE)', () async {
      final code = await cli.run(['scan', '/path/one', '/path/two']);
      expect(
        code,
        equals(64),
        reason: 'two positionals must produce exit 64 (EX_USAGE)',
      );
    });
  });
}
