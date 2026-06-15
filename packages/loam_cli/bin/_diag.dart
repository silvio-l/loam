// TEMPORARY CI diagnostic — to be removed. Prints how config discovery resolves
// in the CI environment so we can pinpoint why the dogfood gate's ignore globs
// are not suppressing test/fixtures there.
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  stderr.writeln('DIAG os=${Platform.operatingSystem}');
  stderr.writeln('DIAG cwd=${Directory.current.path}');
  stderr.writeln('DIAG abs(.)=${p.absolute('.')}');
  stderr.writeln(
    'DIAG loam.yaml@cwd exists='
    '${File(p.join(p.absolute('.'), 'loam.yaml')).existsSync()}',
  );
  stderr.writeln(
    'DIAG .git@repoRoot exists='
    '${Directory(p.join(p.absolute('..'), '..', '.git')).existsSync()}',
  );

  final cfg = await ConfigLoader.load(
    '.',
    knownRuleIds: AnalysisRunner.fullRegistryIds.toSet(),
  );
  stderr.writeln('DIAG ignoreGlobs=${cfg.ignoreGlobs}');

  // If a glob is present, test whether it matches a representative fixture path.
  const sample =
      'test/fixtures/a11y_image_label_fixture/lib/image_missing_label.dart';
  for (final pattern in cfg.ignoreGlobs) {
    stderr.writeln(
      'DIAG Glob("$pattern").matches("$sample")='
      '${Glob(pattern).matches(sample)}',
    );
  }
}
