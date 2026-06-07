import 'dart:io';

import 'package:path/path.dart' as p;

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
/// Returns `null` if no SDK could be located; callers may then fall back to the
/// analyzer's own default resolution.
///
/// The [environment], [resolvedExecutable] and [lookupDartOnPath] seams exist
/// for testing; in production they default to the real platform values.
String? resolveDartSdkPath({
  Map<String, String>? environment,
  String? resolvedExecutable,
  String? Function()? lookupDartOnPath,
}) {
  final env = environment ?? Platform.environment;
  final exe = resolvedExecutable ?? Platform.resolvedExecutable;
  final lookup = lookupDartOnPath ?? _whichDart;

  // 1. Explicit override wins.
  final override = env['DART_SDK'];
  if (override != null && override.trim().isNotEmpty) {
    return p.normalize(override.trim());
  }

  // 2. VM case: <sdk>/bin/dart(.exe) — the SDK root is two levels up.
  final exeBase = p.basenameWithoutExtension(exe).toLowerCase();
  if (exeBase == 'dart') {
    return p.normalize(p.dirname(p.dirname(exe)));
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
    return p.normalize(p.dirname(p.dirname(dartExe)));
  }

  return null;
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
