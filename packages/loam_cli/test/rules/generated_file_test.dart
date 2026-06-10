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

    // Flutter gen-l10n output (default naming convention).
    test('returns true for the gen-l10n umbrella app_localizations.dart', () {
      expect(
        isGeneratedDartFile('lib/core/l10n/app_localizations.dart'),
        isTrue,
      );
    });

    test('returns true for per-locale app_localizations_<locale>.dart', () {
      expect(isGeneratedDartFile('lib/l10n/app_localizations_de.dart'), isTrue);
      expect(isGeneratedDartFile('lib/l10n/app_localizations_en.dart'), isTrue);
      expect(
        isGeneratedDartFile('lib/l10n/app_localizations_pt_BR.dart'),
        isTrue,
      );
    });

    // Guard against over-matching: a file that merely starts similarly but is
    // not the gen-l10n convention must stay un-excluded.
    test('returns false for a hand-written file sharing a prefix', () {
      expect(isGeneratedDartFile('lib/app_localization_helper.dart'), isFalse);
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
