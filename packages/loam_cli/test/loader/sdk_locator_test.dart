@TestOn('vm')
library;

import 'package:loam/src/loader/sdk_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolveDartSdkPath', () {
    test('DART_SDK override wins over everything else', () {
      final sdk = resolveDartSdkPath(
        environment: {'DART_SDK': '/opt/dart-sdk'},
        resolvedExecutable: '/usr/bin/dart',
        lookupDartOnPath: () => fail('lookup must not be consulted'),
      );
      expect(sdk, p.normalize('/opt/dart-sdk'));
    });

    test('blank DART_SDK is ignored (falls through to next strategy)', () {
      final sdk = resolveDartSdkPath(
        environment: {'DART_SDK': '   '},
        resolvedExecutable: '/usr/lib/dart/bin/dart',
        lookupDartOnPath: () => null,
      );
      // Falls through to the VM case: <sdk>/bin/dart -> /usr/lib/dart.
      expect(sdk, p.normalize('/usr/lib/dart'));
    });

    test('VM case: SDK is two levels above the dart executable', () {
      final sdk = resolveDartSdkPath(
        environment: const {},
        resolvedExecutable: '/usr/lib/dart/bin/dart',
        lookupDartOnPath: () => fail('lookup must not be consulted'),
      );
      expect(sdk, p.normalize('/usr/lib/dart'));
    });

    test('AOT case: derives SDK from a dart found on PATH', () {
      final sdk = resolveDartSdkPath(
        environment: const {},
        resolvedExecutable: '/opt/homebrew/Cellar/loam/0.1.0/bin/loam',
        lookupDartOnPath: () => '/usr/lib/dart/bin/dart',
      );
      expect(sdk, p.normalize('/usr/lib/dart'));
    });

    test('returns null when no SDK can be located', () {
      final sdk = resolveDartSdkPath(
        environment: const {},
        resolvedExecutable: '/opt/homebrew/Cellar/loam/0.1.0/bin/loam',
        lookupDartOnPath: () => null,
      );
      expect(sdk, isNull);
    });

    test('default (no seams) resolves a real SDK on the test VM', () {
      // Running under `dart test`, resolvedExecutable is the dart VM, so a real
      // SDK path must come back — guards the production default path.
      expect(resolveDartSdkPath(), isNotNull);
    });
  });
}
