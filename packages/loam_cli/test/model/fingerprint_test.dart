import 'package:loam/loam.dart';
import 'package:test/test.dart';

void main() {
  group('computeFingerprint', () {
    const ruleId = 'unused-public-export';
    const path = 'lib/src/foo.dart';
    const anchor = 'MyClass.foo';

    test(
      'deterministic: same inputs produce same fingerprint across calls',
      () {
        final fp1 = computeFingerprint(
          ruleId: ruleId,
          relativePath: path,
          semanticAnchor: anchor,
        );
        final fp2 = computeFingerprint(
          ruleId: ruleId,
          relativePath: path,
          semanticAnchor: anchor,
        );
        expect(fp1, equals(fp2));
      },
    );

    test('result is exactly 16 hex characters', () {
      final fp = computeFingerprint(
        ruleId: ruleId,
        relativePath: path,
        semanticAnchor: anchor,
      );
      expect(fp, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('discriminating: different ruleId => different fingerprint', () {
      final fp1 = computeFingerprint(
        ruleId: 'rule-a',
        relativePath: path,
        semanticAnchor: anchor,
      );
      final fp2 = computeFingerprint(
        ruleId: 'rule-b',
        relativePath: path,
        semanticAnchor: anchor,
      );
      expect(fp1, isNot(equals(fp2)));
    });

    test('discriminating: different relativePath => different fingerprint', () {
      final fp1 = computeFingerprint(
        ruleId: ruleId,
        relativePath: 'lib/src/a.dart',
        semanticAnchor: anchor,
      );
      final fp2 = computeFingerprint(
        ruleId: ruleId,
        relativePath: 'lib/src/b.dart',
        semanticAnchor: anchor,
      );
      expect(fp1, isNot(equals(fp2)));
    });

    test(
      'discriminating: different semanticAnchor => different fingerprint',
      () {
        final fp1 = computeFingerprint(
          ruleId: ruleId,
          relativePath: path,
          semanticAnchor: 'MyClass.foo',
        );
        final fp2 = computeFingerprint(
          ruleId: ruleId,
          relativePath: path,
          semanticAnchor: 'MyClass.bar',
        );
        expect(fp1, isNot(equals(fp2)));
      },
    );

    test('path normalisation: Windows backslashes equal POSIX slashes', () {
      final fpPosix = computeFingerprint(
        ruleId: ruleId,
        relativePath: 'lib/src/foo.dart',
        semanticAnchor: anchor,
      );
      final fpWindows = computeFingerprint(
        ruleId: ruleId,
        relativePath: r'lib\src\foo.dart',
        semanticAnchor: anchor,
      );
      expect(fpPosix, equals(fpWindows));
    });
  });
}
