import 'package:path/path.dart' as p;

/// Returns `true` when [path] refers to a generated Dart file.
///
/// The check is purely path-based (no I/O, no element model). Recognised
/// generated suffixes:
/// - `*.g.dart` — build_runner JSON/serialisation output
/// - `*.freezed.dart` — Freezed union/value class output
/// - `*.mocks.dart` — Mockito/mocktail generated mocks
///
/// This is the single source of truth used by [ImportGraph] and
/// [PublicApiCollector] to exclude generated files from analysis.
bool isGeneratedDartFile(String path) {
  final basename = p.basename(path);
  return basename.endsWith('.g.dart') ||
      basename.endsWith('.freezed.dart') ||
      basename.endsWith('.mocks.dart');
}
