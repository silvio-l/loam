library;

import 'package:loam/src/progress/render_progress_bar.dart';
import 'package:test/test.dart';

void main() {
  group('renderProgressBar', () {
    // --- width edge cases ---

    test('width 0 returns empty string', () {
      expect(renderProgressBar(current: 5, total: 10, width: 0), equals(''));
    });

    test('width -1 returns empty string', () {
      expect(renderProgressBar(current: 5, total: 10, width: -1), equals(''));
    });

    // --- total <= 0 (indeterminate) ---

    test('total 0 returns indeterminate (space-filled) bar', () {
      expect(
        renderProgressBar(current: 0, total: 0, width: 4),
        equals('[    ]'),
      );
    });

    test('total negative returns indeterminate bar', () {
      expect(
        renderProgressBar(current: 0, total: -5, width: 4),
        equals('[    ]'),
      );
    });

    // --- 0 % ---

    test('0 % — empty bar (all light shade)', () {
      expect(
        renderProgressBar(current: 0, total: 10, width: 10),
        equals('[░░░░░░░░░░]'),
      );
    });

    // --- 100 % ---

    test('100 % — full bar (all full block)', () {
      expect(
        renderProgressBar(current: 10, total: 10, width: 10),
        equals('[██████████]'),
      );
    });

    test('current > total clamps to 100 %', () {
      expect(
        renderProgressBar(current: 15, total: 10, width: 4),
        equals('[████]'),
      );
    });

    // --- 50 % ---

    test('50 % — half full, half empty', () {
      expect(
        renderProgressBar(current: 5, total: 10, width: 10),
        equals('[█████░░░░░]'),
      );
    });

    // --- width 1 (minimum meaningful) ---

    test('width 1, 0 % — single empty char', () {
      expect(renderProgressBar(current: 0, total: 10, width: 1), equals('[░]'));
    });

    test('width 1, 100 % — single full char', () {
      expect(
        renderProgressBar(current: 10, total: 10, width: 1),
        equals('[█]'),
      );
    });

    // --- result length invariant ---

    test('result length is always width + 2 (brackets) for normal input', () {
      const w = 20;
      final bar = renderProgressBar(current: 7, total: 14, width: w);
      expect(bar.length, equals(w + 2));
    });

    test('result length is width + 2 at 0 %', () {
      const w = 15;
      final bar = renderProgressBar(current: 0, total: 100, width: w);
      expect(bar.length, equals(w + 2));
    });

    test('result length is width + 2 at 100 %', () {
      const w = 8;
      final bar = renderProgressBar(current: 8, total: 8, width: w);
      expect(bar.length, equals(w + 2));
    });
  });
}
