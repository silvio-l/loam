import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

/// A cached entry from a previous update check.
class UpdateCheckEntry {
  /// The latest version retrieved during the check.
  final Version latest;

  /// The timestamp when the check was performed (UTC).
  final DateTime checkedAt;

  /// Creates an [UpdateCheckEntry].
  const UpdateCheckEntry({required this.latest, required this.checkedAt});
}

/// Interface for persisting update check results across invocations.
///
/// Implementations are injected into [UpdateChecker] so that the filesystem
/// can be replaced by a [FakeUpdateCheckCache] in tests.
abstract interface class UpdateCheckCache {
  /// Reads the last cached entry.
  ///
  /// Returns `null` when no entry exists or when the cache cannot be read.
  UpdateCheckEntry? read();

  /// Persists [entry] to the cache.
  ///
  /// Silently no-ops on any write error (non-writable directory, etc.).
  void write(UpdateCheckEntry entry);
}

/// Default [UpdateCheckCache] backed by `update_check.json` in the OS cache
/// directory.
///
/// Platform mapping:
/// - macOS:   `~/Library/Caches/loam/`
/// - Linux:   `$XDG_CACHE_HOME/loam/` or `~/.cache/loam/`
/// - Windows: `%LOCALAPPDATA%\loam\`
class FileUpdateCheckCache implements UpdateCheckCache {
  /// Creates a [FileUpdateCheckCache].
  const FileUpdateCheckCache();

  /// Returns the OS-appropriate cache directory path for loam.
  static String get cacheDir {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return p.join(home, 'Library', 'Caches', 'loam');
    } else if (Platform.isLinux) {
      final xdg = Platform.environment['XDG_CACHE_HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        return p.join(xdg, 'loam');
      }
      final home = Platform.environment['HOME'] ?? '';
      return p.join(home, '.cache', 'loam');
    } else if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      return p.join(localAppData, 'loam');
    } else {
      // Fallback for other platforms.
      final home = Platform.environment['HOME'] ?? '';
      return p.join(home, '.cache', 'loam');
    }
  }

  String get _cachePath => p.join(cacheDir, 'update_check.json');

  @override
  UpdateCheckEntry? read() {
    try {
      final file = File(_cachePath);
      if (!file.existsSync()) return null;
      final content = file.readAsStringSync();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final latestStr = decoded['latest'] as String?;
      final checkedAtStr = decoded['checkedAt'] as String?;
      if (latestStr == null || checkedAtStr == null) return null;
      return UpdateCheckEntry(
        latest: Version.parse(latestStr),
        checkedAt: DateTime.parse(checkedAtStr),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void write(UpdateCheckEntry entry) {
    try {
      final dir = Directory(cacheDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final content = jsonEncode({
        'latest': entry.latest.toString(),
        'checkedAt': entry.checkedAt.toIso8601String(),
      });
      File(_cachePath).writeAsStringSync(content);
    } catch (_) {
      // Silently swallow write errors (non-writable directory, etc.).
    }
  }
}
