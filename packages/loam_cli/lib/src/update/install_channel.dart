import 'dart:io';

/// The public release page, used where a channel has no package manager.
const String kReleasesUrl = 'https://github.com/silvio-l/loam/releases/latest';

/// How loam was installed, inferred from the running process.
///
/// loam ships through several channels with **different** upgrade paths.
/// Telling a Homebrew user to run `dart pub global activate loam` installs a
/// *second* copy under `~/.pub-cache/bin` while the Homebrew binary keeps
/// winning on `PATH` — the "update" silently does nothing. Detecting the
/// channel lets loam update (or advise) the binary the user actually runs.
enum InstallChannel {
  /// Installed via Homebrew (`brew install`); upgrade with `brew upgrade loam`.
  homebrew,

  /// Installed via `dart pub global activate loam`; upgrade the same way.
  pubGlobal,

  /// A standalone native binary from a GitHub release (or any other compiled
  /// `loam` executable outside Homebrew).
  binary,

  /// Run from source (`dart run bin/loam.dart`) or an unrecognised layout;
  /// no channel-specific upgrade command — fall back to the pub.dev path.
  unknown,
}

/// Whether [fileName] (an executable's file name) is the Dart VM, which runs
/// loam as a snapshot or script rather than as a compiled binary.
bool isDartVmExecutable(String fileName) {
  final name = fileName.toLowerCase().replaceFirst(RegExp(r'\.exe$'), '');
  return name == 'dart' || name == 'dartvm';
}

/// The install channel plus the path it was inferred from.
///
/// **Pure value object.** Detection is a path test and needs no filesystem
/// probing, so [InstallInfo] is fully testable without a real install. The
/// only impure entry point is [InstallInfo.current], which reads [Platform].
class InstallInfo {
  /// The detected install channel.
  final InstallChannel channel;

  /// The path that identifies the running loam: the native executable for a
  /// compiled binary, the snapshot or script for a Dart-VM run.
  final String executablePath;

  /// Creates an [InstallInfo] with an explicit [channel] and [executablePath].
  const InstallInfo({required this.channel, required this.executablePath});

  /// Infers the install channel (a pure function).
  ///
  /// - [executablePath] is [Platform.resolvedExecutable] (symlinks resolved).
  /// - [scriptPath] is [Platform.script] as a file path, or `null`.
  ///
  /// When the executable is the Dart VM itself (`dart`, `dartvm`), loam runs
  /// as a snapshot or script: a `dart pub global activate` install runs the
  /// snapshot under the pub cache (`.pub-cache` or `global_packages` segment),
  /// anything else is a source run ([InstallChannel.unknown]). Note that the
  /// Dart VM path says nothing about loam — a Homebrew-installed Dart SDK lives
  /// under `Cellar` and must not make a pub-global loam look like Homebrew.
  ///
  /// Otherwise loam is a compiled executable: a `Cellar` segment means
  /// Homebrew (covers `/opt/homebrew`, `/usr/local` and Linuxbrew), a
  /// `.pub-cache` segment means pub-global, everything else is a standalone
  /// [InstallChannel.binary].
  ///
  /// Splits on both `/` and `\` so the same logic holds on Windows.
  factory InstallInfo.fromExecutablePath(
    String executablePath, {
    String? scriptPath,
  }) {
    final exeSegments = _segments(executablePath);
    final exeName = exeSegments.isEmpty ? '' : exeSegments.last.toLowerCase();
    final runsOnDartVm = isDartVmExecutable(exeName);

    if (runsOnDartVm) {
      final script = scriptPath ?? '';
      final scriptSegments = _segments(script);
      final isPubGlobal =
          scriptSegments.contains('.pub-cache') ||
          scriptSegments.contains('global_packages');
      return InstallInfo(
        channel: isPubGlobal
            ? InstallChannel.pubGlobal
            : InstallChannel.unknown,
        executablePath: script.isEmpty ? executablePath : script,
      );
    }

    final channel = exeSegments.contains('Cellar')
        ? InstallChannel.homebrew
        : exeSegments.contains('.pub-cache')
        ? InstallChannel.pubGlobal
        : InstallChannel.binary;
    return InstallInfo(channel: channel, executablePath: executablePath);
  }

  /// Infers the install channel of the currently running process.
  factory InstallInfo.current() {
    String? script;
    try {
      script = Platform.script.toFilePath();
    } catch (_) {
      script = null;
    }
    return InstallInfo.fromExecutablePath(
      Platform.resolvedExecutable,
      scriptPath: script,
    );
  }

  static List<String> _segments(String path) =>
      path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();

  /// The exact command (or instruction) that upgrades **this** install.
  ///
  /// Homebrew installs upgrade via `brew upgrade loam`; a `dart pub global
  /// activate loam` would only shadow them with an unreachable pub-cache copy.
  /// A standalone binary is replaced from the release page. Unknown installs
  /// fall back to the pub.dev command.
  String get upgradeCommand => switch (channel) {
    InstallChannel.homebrew => 'brew upgrade loam',
    InstallChannel.pubGlobal => 'dart pub global activate loam',
    InstallChannel.binary => 'download the new release from $kReleasesUrl',
    InstallChannel.unknown => 'dart pub global activate loam',
  };

  /// A short, human-readable label for the channel (used by `loam --version`).
  String get channelLabel => switch (channel) {
    InstallChannel.homebrew => 'homebrew',
    InstallChannel.pubGlobal => 'pub-global',
    InstallChannel.binary => 'binary',
    InstallChannel.unknown => 'source/unknown',
  };
}
