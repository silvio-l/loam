library;

import 'package:loam/src/rules/generated_file.dart';
import 'package:test/test.dart';

void main() {
  group('isGeneratedDartFile', () {
    // Positive cases — recognised generated suffixes.
    test('returns true for *.g.dart', () {
      expect(isGeneratedDartFile('lib/src/model.g.dart'), isTrue);
    });

    test('returns true for *.freezed.dart', () {
      expect(isGeneratedDartFile('lib/src/model.freezed.dart'), isTrue);
    });

    test('returns true for *.mocks.dart', () {
      expect(isGeneratedDartFile('test/fakes/service.mocks.dart'), isTrue);
    });

    test('returns true for *.g.dart with absolute path', () {
      expect(
        isGeneratedDartFile('/home/user/project/lib/src/foo.g.dart'),
        isTrue,
      );
    });

    // Negative cases — plain Dart and non-Dart paths.
    test('returns false for a regular .dart file', () {
      expect(isGeneratedDartFile('lib/src/model.dart'), isFalse);
    });

    test(
      'returns false for a .dart file whose name merely contains a suffix',
      () {
        // Path contains ".g.dart" in a directory name but the basename does not.
        expect(isGeneratedDartFile('lib/src/model.g.dart.bak'), isFalse);
      },
    );

    test('returns false for a non-Dart text file', () {
      expect(isGeneratedDartFile('lib/src/model.txt'), isFalse);
    });

    test('returns false for a path with no extension', () {
      expect(isGeneratedDartFile('lib/src/model'), isFalse);
    });

    test('returns false for a path whose directory ends in .g.dart', () {
      // The *directory* is named "model.g.dart" but the *file* is plain Dart.
      expect(isGeneratedDartFile('lib/src/model.g.dart/other.dart'), isFalse);
    });
  });
}
