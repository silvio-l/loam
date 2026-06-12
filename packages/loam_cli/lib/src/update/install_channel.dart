import 'dart:io';

/// How loam was installed, inferred from the running executable's path.
///
/// loam ships through two channels with **different** upgrade commands. Telling
/// a Homebrew user to run `dart pub global activate loam` (loam's old,
/// hardcoded advice) installs a *second* copy under `~/.pub-cache/bin` — which
/// is usually not even on `PATH` — while the Homebrew binary keeps winning on
/// `PATH`. The "update" then silently does nothing: the next scan still runs
/// the old binary and its footer still prints the old version. Detecting the
/// channel lets loam print the command that actually upgrades the binary the
/// user is running.
enum InstallChannel {
  /// Installed via Homebrew (`brew install`); upgrade with `brew upgrade loam`.
  homebrew,

  /// Installed via `dart pub global activate loam`; upgrade the same way.
  pubGlobal,

  /// Run from source, or installed in any other location; no
  /// channel-specific upgrade command — fall back to the pub.dev path.
  unknown,
}

/// The install channel plus the resolved executable path it was inferred from.
///
/// **Pure value object.** Detection is a path-segment test on
/// [executablePath] and needs no filesystem probing, so [InstallInfo] is fully
/// testable without a real install. The only impure entry point is
/// [InstallInfo.current], which reads [Platform.resolvedExecutable].
class InstallInfo {
  /// The detected install channel.
  final InstallChannel channel;

  /// The absolute path of the running executable (symlinks already resolved).
  final String executablePath;

  /// Creates an [InstallInfo] with an explicit [channel] and [executablePath].
  const InstallInfo({required this.channel, required this.executablePath});

  /// Infers the install channel from [executablePath] (a pure function).
  ///
  /// [Platform.resolvedExecutable] resolves symlinks, so a Homebrew install
  /// surfaces its real `…/Cellar/loam/<ver>/bin/loam` path — the `bin/loam`
  /// symlink under the Homebrew prefix is followed. Detection is therefore a
  /// path-segment test:
  /// - a `Cellar` segment ⇒ Homebrew (covers `/opt/homebrew`, `/usr/local`
  ///   and Linuxbrew's `/home/linuxbrew/.linuxbrew`);
  /// - a `.pub-cache` segment ⇒ `dart pub global activate`;
  /// - anything else ⇒ [InstallChannel.unknown].
  ///
  /// Splits on both `/` and `\` so the same logic holds on Windows.
  factory InstallInfo.fromExecutablePath(String executablePath) {
    final segments = executablePath.split(RegExp(r'[/\\]'));
    final channel = segments.contains('Cellar')
        ? InstallChannel.homebrew
        : segments.contains('.pub-cache')
        ? InstallChannel.pubGlobal
        : InstallChannel.unknown;
    return InstallInfo(channel: channel, executablePath: executablePath);
  }

  /// Infers the install channel of the currently running process.
  ///
  /// Reads [Platform.resolvedExecutable]; everything else is pure.
  factory InstallInfo.current() =>
      InstallInfo.fromExecutablePath(Platform.resolvedExecutable);

  /// The exact shell command that upgrades the binary on **this** channel.
  ///
  /// Homebrew installs upgrade via `brew upgrade loam`; a `dart pub global
  /// activate loam` would only shadow them with an unreachable pub-cache copy.
  /// Unknown installs fall back to the pub.dev command (the safe default for a
  /// manual binary), and source runs are expected to upgrade out-of-band.
  String get upgradeCommand => switch (channel) {
    InstallChannel.homebrew => 'brew upgrade loam',
    InstallChannel.pubGlobal => 'dart pub global activate loam',
    InstallChannel.unknown => 'dart pub global activate loam',
  };

  /// A short, human-readable label for the channel (used by `loam --version`).
  String get channelLabel => switch (channel) {
    InstallChannel.homebrew => 'homebrew',
    InstallChannel.pubGlobal => 'pub-global',
    InstallChannel.unknown => 'source/unknown',
  };
}
