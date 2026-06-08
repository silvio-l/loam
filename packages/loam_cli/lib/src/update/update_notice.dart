import 'package:pub_semver/pub_semver.dart';

/// Holds the versions required to render an update notice.
///
/// Created by [UpdateChecker.check] when a newer stable version is available
/// on pub.dev. Consumed by [formatUpdateNotice] to produce the stderr line.
class UpdateNotice {
  /// The version of the currently installed [loam] binary.
  final Version currentVersion;

  /// The latest stable version available on pub.dev.
  final Version latestVersion;

  /// The exact shell command the user should run to update.
  final String updateCommand;

  /// Creates an [UpdateNotice].
  const UpdateNotice({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateCommand,
  });
}

/// Formats [notice] into a single stderr line.
///
/// The returned string matches the specified format:
/// `loam: Update verfügbar X.Y.Z → A.B.C · dart pub global activate loam`
///
/// This is a pure function — no side effects, no I/O.
String formatUpdateNotice(UpdateNotice notice) =>
    'loam: Update verfügbar ${notice.currentVersion} → '
    '${notice.latestVersion} · ${notice.updateCommand}';
