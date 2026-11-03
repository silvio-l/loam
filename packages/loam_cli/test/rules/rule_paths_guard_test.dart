@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Guard: rules and their collectors build finding paths only through
/// `projectRelativePosixPath`. A bare `relative(` call yields backslashes on
/// Windows, and then `// loam-ignore:` directives and baseline entries no
/// longer match (loam #29). Checking the source keeps the guard effective on
/// every host, not only on Windows. The helper's Windows behaviour is proven
/// in test/model/project_path_test.dart.
void main() {
  final relativeCall = RegExp(r'\brelative\(');

  test('no rule derives finding paths with a bare relative() call', () {
    final rulesDir = Directory(
      p.join(Directory.current.path, 'lib', 'src', 'rules'),
    );
    final ruleFiles = rulesDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(ruleFiles, isNotEmpty, reason: 'no rule files found');

    final offenders = [
      for (final f in ruleFiles)
        if (relativeCall.hasMatch(f.readAsStringSync())) p.basename(f.path),
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'use projectRelativePosixPath for Finding.filePath',
    );
  });
}
