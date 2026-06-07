@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/config/config_scaffold.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;

void main() {
  // ---------------------------------------------------------------------------
  // AC3: `loam init` writes loam.yaml to the project root.
  // AC4: Existing loam.yaml is not overwritten; clear message, exit != 0.
  // AC5: Unit-Test (covered in config_scaffold_test.dart) +
  //      CLI-Test (this file): write / no-overwrite.
  // ---------------------------------------------------------------------------

  group('loam init', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('loam_init_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // -------------------------------------------------------------------------
    // AC3: writes loam.yaml when none exists → exit 0.
    // -------------------------------------------------------------------------
    test(
      'creates loam.yaml in project root when file is absent → exit 0',
      () async {
        final code = await cli.run(['init', '--project-root', tempDir.path]);

        expect(code, equals(0), reason: 'loam init should succeed with exit 0');

        final target = File(p.join(tempDir.path, ConfigLoader.fileName));
        expect(
          target.existsSync(),
          isTrue,
          reason: 'loam.yaml must be created',
        );
      },
    );

    test('written loam.yaml contains expected scaffold content', () async {
      await cli.run(['init', '--project-root', tempDir.path]);

      final target = File(p.join(tempDir.path, ConfigLoader.fileName));
      final written = target.readAsStringSync();

      // Content must match ConfigScaffold.generate() exactly (deterministic).
      expect(written, equals(ConfigScaffold.generate()));
    });

    test(
      'written loam.yaml is loadable by ConfigLoader without error',
      () async {
        await cli.run(['init', '--project-root', tempDir.path]);

        // AC2 verification at CLI level: load the written file via ConfigLoader.
        expect(
          () async => ConfigLoader.load(tempDir.path),
          returnsNormally,
          reason: 'written loam.yaml must be valid for ConfigLoader',
        );
      },
    );

    // -------------------------------------------------------------------------
    // AC4: no-overwrite — existing loam.yaml is preserved → exit 1.
    // -------------------------------------------------------------------------
    test('refuses to overwrite existing loam.yaml → exit 1', () async {
      // Plant a pre-existing loam.yaml with distinct content.
      const existingContent = '# pre-existing config\nrules:\n';
      final target = File(p.join(tempDir.path, ConfigLoader.fileName));
      target.writeAsStringSync(existingContent);

      final code = await cli.run(['init', '--project-root', tempDir.path]);

      expect(
        code,
        equals(1),
        reason: 'loam init must exit 1 when loam.yaml already exists',
      );

      // The pre-existing file must be unchanged.
      expect(
        target.readAsStringSync(),
        equals(existingContent),
        reason: 'pre-existing loam.yaml must not be overwritten',
      );
    });

    test('uses current directory as default project-root '
        '(no --project-root flag)', () async {
      // Run without --project-root; the command defaults to
      // Directory.current.path.  We only verify the command runs without
      // crashing (exit 0 or 1 depending on whether loam.yaml already exists
      // in the package root — we do NOT delete any real files).
      //
      // We check it is a valid int exit code.
      final code = await cli.run(['init']);
      expect(code, anyOf(0, 1), reason: 'must exit 0 or 1 (not crash)');

      // Clean up if init created a file in the current directory.
      final created = File(
        p.join(Directory.current.path, ConfigLoader.fileName),
      );
      if (created.existsSync()) {
        // Only remove if its content matches the scaffold (i.e. we created it).
        final content = created.readAsStringSync();
        if (content == ConfigScaffold.generate()) {
          created.deleteSync();
        }
      }
    });
  });
}
