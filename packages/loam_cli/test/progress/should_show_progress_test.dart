library;

import 'package:loam/src/progress/should_show_progress.dart';
import 'package:test/test.dart';

void main() {
  group('shouldShowProgress', () {
    // Helper: call with defaults (TTY=true, no flag, no env).
    bool check({
      bool isTty = true,
      bool noProgressFlag = false,
      Map<String, String> environment = const {},
    }) => shouldShowProgress(
      isTty: isTty,
      noProgressFlag: noProgressFlag,
      environment: environment,
    );

    test('on when interactive TTY, no flag, no CI, no env', () {
      expect(check(), isTrue);
    });

    // --- noProgressFlag (highest precedence) ---

    test('off when --no-progress flag is set (even with TTY)', () {
      expect(check(noProgressFlag: true), isFalse);
    });

    test('--no-progress takes precedence over everything', () {
      // flag overrides TTY=true, no CI, no LOAM_NO_PROGRESS
      expect(
        check(noProgressFlag: true, isTty: true, environment: const {}),
        isFalse,
      );
    });

    // --- LOAM_NO_PROGRESS env var ---

    test('off when LOAM_NO_PROGRESS is set to "1"', () {
      expect(check(environment: const {'LOAM_NO_PROGRESS': '1'}), isFalse);
    });

    test('off when LOAM_NO_PROGRESS is set to "true"', () {
      expect(check(environment: const {'LOAM_NO_PROGRESS': 'true'}), isFalse);
    });

    test('on when LOAM_NO_PROGRESS is empty string (treated as not set)', () {
      expect(check(environment: const {'LOAM_NO_PROGRESS': ''}), isTrue);
    });

    // --- CI env var ---

    test('off under CI=true', () {
      expect(check(environment: const {'CI': 'true'}), isFalse);
    });

    test('off under CI=1', () {
      expect(check(environment: const {'CI': '1'}), isFalse);
    });

    test('on when CI is empty string (treated as not-CI)', () {
      expect(check(environment: const {'CI': ''}), isTrue);
    });

    // --- isTty ---

    test('off when not attached to a terminal (pipe/redirect)', () {
      expect(check(isTty: false), isFalse);
    });

    // --- Precedence chain ---

    test('LOAM_NO_PROGRESS takes precedence over CI and isTty', () {
      // All three would suppress — verify LOAM_NO_PROGRESS alone is enough.
      expect(
        check(
          isTty: true,
          noProgressFlag: false,
          environment: const {'LOAM_NO_PROGRESS': '1', 'CI': 'true'},
        ),
        isFalse,
      );
    });

    test('flag beats LOAM_NO_PROGRESS and CI', () {
      expect(
        check(
          noProgressFlag: true,
          isTty: true,
          environment: const {'LOAM_NO_PROGRESS': '', 'CI': ''},
        ),
        isFalse,
      );
    });

    test('CI=true beats isTty=true', () {
      expect(check(isTty: true, environment: const {'CI': 'true'}), isFalse);
    });

    test('isTty=false beats absence of any other suppressors', () {
      expect(check(isTty: false, environment: const {}), isFalse);
    });
  });
}
