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

    test('Flutter wrapper: redirects into bin/cache/dart-sdk (AOT case)', () {
      // A standard Flutter install puts <flutterRoot>/bin on PATH, where
      // `dart` is a wrapper script — not the real SDK. The real Dart SDK lives
      // at <flutterRoot>/bin/cache/dart-sdk. Naively going two levels up yields
      // the Flutter root (no lib/_internal), crashing the analyzer.
      const flutterRoot = '/opt/homebrew/share/flutter';
      final sdk = resolveDartSdkPath(
        environment: const {},
        resolvedExecutable: '/opt/homebrew/Cellar/loam/0.1.0/bin/loam',
        lookupDartOnPath: () => '$flutterRoot/bin/dart',
        directoryExists: (path) =>
            path == p.normalize('$flutterRoot/bin/cache/dart-sdk'),
      );
      expect(sdk, p.normalize('$flutterRoot/bin/cache/dart-sdk'));
    });

    test('Flutter wrapper: redirects into bin/cache/dart-sdk (VM case)', () {
      // Same topology when loam runs on the VM via the Flutter `dart` wrapper.
      const flutterRoot = '/opt/homebrew/share/flutter';
      final sdk = resolveDartSdkPath(
        environment: const {},
        resolvedExecutable: '$flutterRoot/bin/dart',
        lookupDartOnPath: () => fail('lookup must not be consulted'),
        directoryExists: (path) =>
            path == p.normalize('$flutterRoot/bin/cache/dart-sdk'),
      );
      expect(sdk, p.normalize('$flutterRoot/bin/cache/dart-sdk'));
    });

    test('non-Flutter dart: no cache/dart-sdk dir, returns plain root', () {
      final sdk = resolveDartSdkPath(
        environment: const {},
        resolvedExecutable: '/opt/homebrew/Cellar/loam/0.1.0/bin/loam',
        lookupDartOnPath: () => '/usr/lib/dart/bin/dart',
        directoryExists: (_) => false,
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

  group('isUsableDartSdk', () {
    test('true when lib/_internal exists under the SDK path', () {
      expect(
        isUsableDartSdk(
          '/usr/lib/dart',
          directoryExists: (path) =>
              path == p.join('/usr/lib/dart', 'lib', '_internal'),
        ),
        isTrue,
      );
    });

    test('false when lib/_internal is missing (e.g. a Flutter root)', () {
      expect(
        isUsableDartSdk(
          '/opt/homebrew/share/flutter',
          directoryExists: (_) => false,
        ),
        isFalse,
      );
    });

    test('default (no seam) accepts a real SDK on the test VM', () {
      final sdk = resolveDartSdkPath();
      expect(sdk, isNotNull);
      expect(isUsableDartSdk(sdk!), isTrue);
    });
  });

  group('SdkResolutionException.notFound', () {
    test('names DART_SDK and the Flutter cache path when a root resolved', () {
      final ex = SdkResolutionException.notFound(
        resolved: '/opt/homebrew/share/flutter',
      );
      expect(ex.resolvedPath, '/opt/homebrew/share/flutter');
      expect(ex.message, contains('DART_SDK='));
      expect(
        ex.message,
        contains(
          p.join('/opt/homebrew/share/flutter', 'bin', 'cache', 'dart-sdk'),
        ),
      );
      // Steering, not a stacktrace.
      expect(ex.message, isNot(contains('#0')));
    });

    test('handles a null resolved path with a generic placeholder hint', () {
      final ex = SdkResolutionException.notFound();
      expect(ex.resolvedPath, isNull);
      expect(ex.message, contains('DART_SDK='));
      expect(ex.message, contains('<flutterRoot>/bin/cache/dart-sdk'));
    });
  });
}
