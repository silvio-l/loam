import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the fixture package at [fixtureDir] when its
/// `.dart_tool/package_config.json` is missing.
///
/// Fixtures are standalone mini packages with `package:` self-imports. A fresh
/// checkout has no package_config for them (`.dart_tool/` is gitignored), so
/// every file fails to resolve and the loader reports a `LoadFileError`. Call
/// this before loading a fixture so the suite does not depend on a manual
/// `dart pub get` per fixture (what `scripts/ci-gates.sh` does on Linux/macOS).
Future<String> ensureFixtureResolved(String fixtureDir) async {
  final config = File(p.join(fixtureDir, '.dart_tool', 'package_config.json'));
  // Test files run in parallel isolates and may share a fixture: retry once
  // when a concurrent `pub get` is still writing.
  for (var attempt = 0; attempt < 2 && !config.existsSync(); attempt++) {
    final result = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: fixtureDir);
    if (result.exitCode != 0 && !config.existsSync() && attempt == 1) {
      throw StateError(
        'dart pub get --offline failed in $fixtureDir: ${result.stderr}',
      );
    }
  }
  return fixtureDir;
}
