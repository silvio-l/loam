import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:loam/src/update/integrity.dart';
import 'package:loam/src/update/self_updater.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

/// Serves fixed bytes per URL path suffix and records the requests.
class _FakeDownloads {
  _FakeDownloads(this.files);

  final Map<String, List<int>?> files;
  final requested = <Uri>[];

  Future<List<int>?> call(Uri uri, {required int maxBytes}) async {
    requested.add(uri);
    for (final entry in files.entries) {
      if (uri.path.endsWith('/${entry.key}')) return entry.value;
    }
    return null;
  }
}

void main() {
  final target = Version.parse('0.1.16');
  const asset = 'loam-macos-arm64.tar.gz';
  final archive = utf8.encode('fake archive bytes');
  final digest = sha256.convert(archive).toString();

  group('integrity helpers', () {
    test('parseSha256File accepts bare and sha256sum style, rejects junk', () {
      expect(parseSha256File('$digest\n'), digest);
      expect(parseSha256File('${digest.toUpperCase()}  $asset'), digest);
      expect(parseSha256File('not-a-digest'), isNull);
      expect(parseSha256File(''), isNull);
    });

    test('sha256Matches detects any change', () {
      expect(sha256Matches(archive, digest), isTrue);
      expect(sha256Matches([...archive, 0], digest), isFalse);
      expect(sha256Matches(archive, 'abc'), isFalse);
    });

    test('release assets exist only for the published platforms', () {
      expect(binaryAssetName(Abi.macosArm64), 'loam-macos-arm64.tar.gz');
      expect(binaryAssetName(Abi.linuxX64), 'loam-linux-x86_64.tar.gz');
      expect(binaryAssetName(Abi.macosX64), isNull);
      expect(binaryAssetName(Abi.windowsX64), isNull);
    });

    test('download URLs are HTTPS and name the exact version', () {
      final uri = releaseAssetUri(target, asset);
      expect(uri.scheme, 'https');
      expect(uri.path, endsWith('/releases/download/v0.1.16/$asset'));
    });

    test('parseVersionOutput reads line 1 of `loam --version`', () {
      expect(
        parseVersionOutput('loam 0.1.16\ninstall: binary · /x'),
        Version.parse('0.1.16'),
      );
      expect(parseVersionOutput('something else'), isNull);
    });

    test('httpsDownload refuses plain HTTP without any request', () async {
      expect(
        await httpsDownload(Uri.http('example.com', '/x'), maxBytes: 10),
        isNull,
      );
    });
  });

  group('BinaryInstaller fails closed', () {
    Future<(String?, List<List<int>>)> install(
      Map<String, List<int>?> files,
    ) async {
      final swapped = <List<int>>[];
      final installer = BinaryInstaller(
        asset: asset,
        download: _FakeDownloads(files).call,
        swap: (bytes, version) async {
          swapped.add(bytes);
          return null;
        },
      );
      return (await installer.install(target), swapped);
    }

    test('matching checksum → archive is swapped in', () async {
      final (reason, swapped) = await install({
        '$asset.sha256': utf8.encode('$digest\n'),
        asset: archive,
      });
      expect(reason, isNull);
      expect(swapped, [archive]);
    });

    test('checksum mismatch → nothing is swapped', () async {
      final (reason, swapped) = await install({
        '$asset.sha256': utf8.encode('${'0' * 64}\n'),
        asset: archive,
      });
      expect(reason, contains('checksum mismatch'));
      expect(swapped, isEmpty);
    });

    test('missing or malformed checksum file → nothing is swapped', () async {
      final missing = await install({asset: archive});
      expect(missing.$1, contains('no checksum'));
      expect(missing.$2, isEmpty);

      final malformed = await install({
        '$asset.sha256': utf8.encode('<html>not found</html>'),
        asset: archive,
      });
      expect(malformed.$1, contains('malformed checksum'));
      expect(malformed.$2, isEmpty);
    });

    test('failed archive download → nothing is swapped', () async {
      final (reason, swapped) = await install({
        '$asset.sha256': utf8.encode(digest),
      });
      expect(reason, contains('download'));
      expect(swapped, isEmpty);
    });
  });

  group('PubGlobalInstaller', () {
    test(
      'activates exactly the checked version with the running SDK',
      () async {
        final calls = <List<String>>[];
        final installer = PubGlobalInstaller(
          dartExecutable: '/sdk/bin/dart',
          runProcess: (exe, args) async {
            calls.add([exe, ...args]);
            return ProcessResult(0, 0, '', '');
          },
        );
        expect(await installer.install(target), isNull);
        expect(calls.single, [
          '/sdk/bin/dart',
          'pub',
          'global',
          'activate',
          'loam',
          '0.1.16',
        ]);
      },
    );

    test('non-zero exit → failure reason', () async {
      final installer = PubGlobalInstaller(
        dartExecutable: 'dart',
        runProcess: (exe, args) async => ProcessResult(0, 69, '', ''),
      );
      expect(await installer.install(target), contains('exit 69'));
    });
  });
}
