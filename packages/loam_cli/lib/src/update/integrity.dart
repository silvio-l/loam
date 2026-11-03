import 'dart:ffi' show Abi;

import 'package:crypto/crypto.dart';
import 'package:pub_semver/pub_semver.dart';

/// The GitHub repository that hosts the release binaries.
const String kReleaseRepository = 'silvio-l/loam';

/// Whether this executable is an official release build. Only the official release
/// build (tool/release-local.sh) compiles with `-Dloam.release_binary=true`; every other compiled
/// binary (a local `dart compile exe`) is `false` and never replaces itself.
const bool kIsReleaseBinary = bool.fromEnvironment('loam.release_binary');

/// Upper bound for a downloaded release archive. A real archive is a few tens
/// of megabytes; anything larger is refused before it fills the disk.
const int kMaxArchiveBytes = 200 * 1024 * 1024;

/// The release asset that holds the native binary for [abi], or `null` when
/// loam publishes no binary for that platform (then the binary cannot update
/// itself and the user gets the manual command).
String? binaryAssetName(Abi abi) => switch (abi) {
  Abi.macosArm64 => 'loam-macos-arm64.tar.gz',
  Abi.linuxX64 => 'loam-linux-x86_64.tar.gz',
  _ => null,
};

/// The HTTPS download URL of [asset] in the release of [version].
Uri releaseAssetUri(Version version, String asset) => Uri.https(
  'github.com',
  '/$kReleaseRepository/releases/download/v$version/$asset',
);

final RegExp _sha256Hex = RegExp(r'^[0-9a-fA-F]{64}$');

/// Parses a `.sha256` file as written by tool/release-local.sh (the bare hex
/// digest, or `sha256sum` style `<hex>  <file>`). Returns the lower-case hex
/// digest, or `null` when the content holds no valid SHA-256.
String? parseSha256File(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return null;
  final first = trimmed.split(RegExp(r'\s+')).first;
  return _sha256Hex.hasMatch(first) ? first.toLowerCase() : null;
}

/// Whether [bytes] hash to [expectedHex] (SHA-256, case-insensitive).
///
/// Compares every character so the run time does not depend on where the
/// first difference sits.
bool sha256Matches(List<int> bytes, String expectedHex) {
  final actual = sha256.convert(bytes).toString();
  final expected = expectedHex.toLowerCase();
  if (actual.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return diff == 0;
}

/// Parses the first line of `loam --version` (`loam <version>`), or `null`.
Version? parseVersionOutput(String output) {
  final firstLine = output.trim().split('\n').first.trim();
  final match = RegExp(r'^loam (\S+)$').firstMatch(firstLine);
  if (match == null) return null;
  try {
    return Version.parse(match.group(1)!);
  } on FormatException {
    return null;
  }
}
