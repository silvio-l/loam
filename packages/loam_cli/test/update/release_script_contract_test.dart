import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:loam/src/update/integrity.dart';
import 'package:test/test.dart';

void main() {
  // The release script and the Homebrew template write the assets the
  // self-updater downloads; a rename on either side only shows up at release
  // time, so the shared names are pinned here.
  test('release script and formula use the self-updater asset names', () {
    final script = File('../../tool/release-local.sh').readAsStringSync();
    final formula = File('../../tool/homebrew/loam.rb.tmpl').readAsStringSync();
    for (final abi in [Abi.macosArm64, Abi.linuxX64]) {
      final asset = binaryAssetName(abi)!;
      expect(script, contains(asset), reason: 'release-local.sh: $asset');
      expect(formula, contains(asset), reason: 'loam.rb.tmpl: $asset');
    }
  });

  // release-local.sh builds every binary with the SDK pinned in release.yml
  // (#94); qa.yml has to check the code with that same SDK.
  test('qa and release workflows pin the same Dart SDK', () {
    final pin = RegExp(r"sdk: '([0-9.]+)'");
    String pinOf(String file) => pin
        .firstMatch(File('../../.github/workflows/$file').readAsStringSync())!
        .group(1)!;
    expect(pinOf('qa.yml'), pinOf('release.yml'));
  });
}
