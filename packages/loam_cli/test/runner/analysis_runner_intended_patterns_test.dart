@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Hand-over point: `loam.yaml` → [ConfigLoader] → [AnalysisRunner] → rules.
void main() {
  late Directory configDir;

  setUp(() {
    configDir = Directory.systemTemp.createTempSync('loam_intended_');
    Directory(p.join(configDir.path, '.git')).createSync();
  });

  tearDown(() => configDir.deleteSync(recursive: true));

  String fixture(String name) =>
      p.join(Directory.current.path, 'test', 'fixtures', name);

  Future<List<String>> run(
    String fixtureName,
    String yaml,
    String ruleId,
  ) async {
    File(p.join(configDir.path, 'loam.yaml')).writeAsStringSync(yaml);
    final config = await ConfigLoader.load(configDir.path);
    final findings = await AnalysisRunner(
      config: config,
    ).run(fixture(fixtureName));
    return [
      for (final f in findings)
        if (f.ruleId == ruleId) f.message,
    ];
  }

  test(
    'code_duplicates.boilerplate: false reports boilerplate again',
    () async {
      final skipped = await run('boilerplate_fixture', '', 'code-duplicates');
      final reported = await run(
        'boilerplate_fixture',
        'code_duplicates:\n  boilerplate: false\n',
        'code-duplicates',
      );
      expect(reported.length, greaterThan(skipped.length));
    },
  );

  test(
    'unused_public_exports.annotations suppresses the annotated symbol',
    () async {
      final base = (await run(
        'reserved_annotations_fixture',
        '',
        'unused-public-exports',
      )).join('\n');
      final configured = (await run(
        'reserved_annotations_fixture',
        'unused_public_exports:\n  annotations: [Keep]\n',
        'unused-public-exports',
      )).join('\n');
      expect(base, contains('ReservedByKeep'));
      expect(configured, isNot(contains('ReservedByKeep')));
      expect(configured, contains('`TrulyUnused`'));
    },
  );
}
