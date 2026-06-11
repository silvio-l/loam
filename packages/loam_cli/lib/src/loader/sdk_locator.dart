import 'dart:io';

import 'package:path/path.dart' as p;

/// Thrown when loam cannot locate a usable Dart SDK for the analyzer.
///
/// This is a **precondition failure**, not a per-file analysis failure: without
/// an SDK the analyzer cannot resolve `dart:` libraries at all, so every file
/// would fail identically. Rather than crash with a raw `PathNotFoundException`
/// from deep inside the analyzer — opaque noise for a human and an AI agent
/// alike — the loader raises this with an actionable, steering [message].
class SdkResolutionException implements Exception {
  /// Creates an [SdkResolutionException] with a ready-to-print [message].
  const SdkResolutionException(this.message, {this.resolvedPath});

  /// Human- and agent-readable explanation including the concrete remedy
  /// (set `DART_SDK`). Safe to print verbatim to stderr — no stacktrace.
  final String message;

  /// The SDK path loam resolved but found unusable, if any (`null` when no
  /// candidate could be derived at all).
  final String? resolvedPath;

  @override
  String toString() => message;

  /// Builds the steering message shown to the user when no usable SDK is found.
  ///
  /// [resolved] is the candidate path loam derived (or `null` if none). The
  /// message names the concrete fix — set `DART_SDK` to a real SDK, pointing at
  /// `<flutterRoot>/bin/cache/dart-sdk` for Flutter installs.
  static SdkResolutionException notFound({String? resolved}) {
    final flutterCacheHint = resolved == null
        ? '<flutterRoot>/bin/cache/dart-sdk'
        : p.normalize(p.join(resolved, 'bin', 'cache', 'dart-sdk'));
    final detail = resolved == null
        ? 'No Dart SDK could be located via DART_SDK, the running '
              'executable, or a `dart` on PATH.'
        : 'The resolved path "$resolved" is not a usable Dart SDK '
              '(missing lib/_internal). This usually means only Flutter\'s '
              'bin/ is on PATH, where `dart` is a wrapper — the real SDK lives '
              'under bin/cache/dart-sdk.';
    return SdkResolutionException(
      'loam could not locate a usable Dart SDK.\n'
      '$detail\n'
      'Fix it by pointing DART_SDK at a real SDK, e.g.:\n'
      '    DART_SDK=$flutterCacheHint loam <command>\n'
      'or run loam from a shell where `dart --version` resolves to a real '
      'Dart SDK.',
      resolvedPath: resolved,
    );
  }
}

/// Resolves an absolute Dart SDK path for the analyzer.
///
/// The Dart `analyzer` needs a real SDK on disk to resolve `dart:` libraries
/// (e.g. `dart:core`). When loam runs on the Dart VM (`dart pub global run`),
/// the analyzer can derive the SDK from [Platform.resolvedExecutable] — that is
/// the `dart` binary, with the SDK right beside it. But when loam is shipped as
/// a **compiled AOT executable** (the Homebrew tap), the running executable is
/// `loam` itself with no SDK next to it; the analyzer then crashes with a
/// `PathNotFoundException` on `lib/_internal/.../libraries.dart`.
///
/// This helper resolves the SDK explicitly, robust for both cases, in order:
///   1. A `DART_SDK` environment override, if set.
///   2. The running executable, when it *is* the Dart VM (`dart`).
///   3. A `dart` executable discovered on `PATH` (the AOT case) — loam's
///      audience are Dart/Flutter developers, so an SDK is always installed.
///
/// In cases 2 and 3 the SDK root is normally two levels above the `dart`
/// executable (`<sdk>/bin/dart`). A **Flutter** install breaks that assumption:
/// it puts `<flutterRoot>/bin` on `PATH`, where `dart` is a thin wrapper script
/// (not a symlink into the SDK on macOS/Linux). Going two levels up then yields
/// the Flutter checkout root, which has no `lib/_internal` and crashes the
/// analyzer. The real Dart SDK lives at `<flutterRoot>/bin/cache/dart-sdk`, so
/// whenever that directory exists beside the `dart` wrapper we redirect into it.
///
/// Returns `null` if no SDK could be located; callers may then fall back to the
/// analyzer's own default resolution.
///
/// The [environment], [resolvedExecutable], [lookupDartOnPath] and
/// [directoryExists] seams exist for testing; in production they default to the
/// real platform values.
String? resolveDartSdkPath({
  Map<String, String>? environment,
  String? resolvedExecutable,
  String? Function()? lookupDartOnPath,
  bool Function(String path)? directoryExists,
}) {
  final env = environment ?? Platform.environment;
  final exe = resolvedExecutable ?? Platform.resolvedExecutable;
  final lookup = lookupDartOnPath ?? _whichDart;
  final dirExists = directoryExists ?? (path) => Directory(path).existsSync();

  // 1. Explicit override wins.
  final override = env['DART_SDK'];
  if (override != null && override.trim().isNotEmpty) {
    return p.normalize(override.trim());
  }

  // 2. VM case: <sdk>/bin/dart(.exe) — the SDK root is two levels up.
  final exeBase = p.basenameWithoutExtension(exe).toLowerCase();
  if (exeBase == 'dart') {
    return _sdkRootForDartExe(exe, dirExists);
  }

  // 3. AOT case: derive the SDK from a `dart` on PATH.
  final onPath = lookup();
  if (onPath != null && onPath.trim().isNotEmpty) {
    var dartExe = onPath.trim();
    try {
      // Resolve symlinks so e.g. /opt/homebrew/bin/dart points at the real
      // <sdk>/bin/dart inside the Cellar/libexec.
      dartExe = File(dartExe).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Fall back to the unresolved path if symlink resolution fails.
    }
    return _sdkRootForDartExe(dartExe, dirExists);
  }

  return null;
}

/// Derives the SDK root from a `<root>/bin/dart` executable path, accounting for
/// the Flutter wrapper layout.
///
/// Normally the SDK root is two levels up. But when [dartExe] is a Flutter
/// `bin/dart` wrapper, the real SDK sits at `<flutterRoot>/bin/cache/dart-sdk`;
/// if that directory exists we return it instead of the (analyzer-unusable)
/// Flutter checkout root.
String _sdkRootForDartExe(String dartExe, bool Function(String) dirExists) {
  final binDir = p.dirname(dartExe); // <root>/bin
  final flutterSdk = p.normalize(p.join(binDir, 'cache', 'dart-sdk'));
  if (dirExists(flutterSdk)) {
    return flutterSdk;
  }
  return p.normalize(p.dirname(binDir));
}

/// Whether [sdkPath] points at a directory the analyzer can use as a Dart SDK.
///
/// The analyzer's `FolderBasedDartSdk` reads the SDK's library map from
/// `<sdk>/lib/_internal/…/libraries.dart`. A path missing that `lib/_internal`
/// directory (e.g. a Flutter checkout root, which has no top-level `lib/`)
/// makes the analyzer throw a `PathNotFoundException` during
/// `AnalysisContextCollection` construction. Validating up front lets callers
/// fail with an actionable message instead of a raw stacktrace.
///
/// The [directoryExists] seam exists for testing; in production it defaults to
/// a real filesystem check.
bool isUsableDartSdk(
  String sdkPath, {
  bool Function(String path)? directoryExists,
}) {
  final dirExists = directoryExists ?? (path) => Directory(path).existsSync();
  return dirExists(p.join(sdkPath, 'lib', '_internal'));
}

/// Locates a `dart` executable on `PATH` via the platform's lookup command.
/// Returns the first match, or `null` if none is found.
String? _whichDart() {
  final cmd = Platform.isWindows ? 'where' : 'which';
  try {
    final result = Process.runSync(cmd, ['dart']);
    if (result.exitCode == 0) {
      final out = (result.stdout as String).trim();
      if (out.isNotEmpty) {
        return out.split(RegExp(r'\r?\n')).first.trim();
      }
    }
  } on ProcessException {
    // `which`/`where` unavailable — fall through to null.
  }
  return null;
}
