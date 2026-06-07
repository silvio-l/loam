@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/config/config_scaffold.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // AC1: ConfigScaffold produces a deterministic string (golden test).
  // ---------------------------------------------------------------------------

  group('ConfigScaffold.generate()', () {
    test('returns non-empty string', () {
      final content = ConfigScaffold.generate();
      expect(content, isNotEmpty);
    });

    test('is deterministic — two calls return identical strings', () {
      final a = ConfigScaffold.generate();
      final b = ConfigScaffold.generate();
      expect(a, equals(b));
    });

    test('ends with a single trailing newline (POSIX convention)', () {
      final content = ConfigScaffold.generate();
      expect(content.endsWith('\n'), isTrue, reason: 'must end with newline');
      expect(
        content.endsWith('\n\n'),
        isFalse,
        reason: 'must not have double trailing newline',
      );
    });

    test('uses only POSIX line endings (no \\r\\n)', () {
      final content = ConfigScaffold.generate();
      expect(content.contains('\r'), isFalse, reason: 'no carriage returns');
    });

    test('contains required top-level YAML keys', () {
      final content = ConfigScaffold.generate();
      // Both `rules:` and `ignore:` must appear as active YAML keys.
      expect(content, contains('rules:'));
      expect(content, contains('ignore:'));
    });

    test('golden — structural markers are present', () {
      // Authoritative golden: changing ConfigScaffold._content is a deliberate,
      // reviewed change; update these expectations in the same commit.
      final content = ConfigScaffold.generate();
      expect(content, contains('# loam.yaml — loam.dev configuration'));
      expect(content, contains('rules:'));
      expect(content, contains('ignore:'));
      // The one known ruleId must appear (as a comment showing the syntax).
      expect(content, contains('unused-public-exports'));
      expect(
        content,
        contains('loam.dev'),
        reason: 'product name must appear in scaffold',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC2: The generated file is a valid loam.yaml that ConfigLoader loads
  //       without raising ConfigLoadException.
  // ---------------------------------------------------------------------------

  group('ConfigScaffold — ConfigLoader roundtrip', () {
    test('generated content loads via ConfigLoader without error', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'loam_scaffold_test_',
      );
      try {
        // Write the scaffold to the temp dir so ConfigLoader can read it.
        final file = File(p.join(tempDir.path, ConfigLoader.fileName));
        file.writeAsStringSync(ConfigScaffold.generate());

        // Must not throw ConfigLoadException.
        final config = await ConfigLoader.load(
          tempDir.path,
          knownRuleIds: AnalysisRunner.fullRegistryIds.toSet(),
        );

        // The scaffold has no active rule toggles (all commented out),
        // so both collections must be empty.
        expect(
          config.ruleToggles,
          isEmpty,
          reason:
              'scaffold example toggles are YAML comments — no active toggles',
        );
        expect(
          config.ignoreGlobs,
          isEmpty,
          reason: 'scaffold example globs are YAML comments — no active globs',
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
