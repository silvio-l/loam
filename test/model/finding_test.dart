import 'package:loam/loam.dart';
import 'package:test/test.dart';

void main() {
  group('Finding', () {
    test('renders line-only location when column is null', () {
      const finding = Finding(
        ruleId: 'unused-public-exports',
        severity: Severity.warning,
        filePath: 'lib/src/foo.dart',
        line: 12,
        message: 'Unused public export.',
        fingerprint: 'abc123',
      );

      expect(finding.column, isNull);
      expect(
        finding.toString(),
        '[unused-public-exports] lib/src/foo.dart:12 Unused public export.',
      );
    });

    test('renders line:column location when column is present', () {
      const finding = Finding(
        ruleId: 'empty-catch',
        severity: Severity.error,
        filePath: 'lib/src/bar.dart',
        line: 8,
        column: 5,
        message: 'Empty catch block swallows the error.',
        fingerprint: 'def456',
      );

      expect(finding.column, 5);
      expect(
        finding.toString(),
        '[empty-catch] lib/src/bar.dart:8:5 Empty catch block swallows the error.',
      );
    });
  });
}
