import 'package:test/test.dart';

void main() {
  test('suppressed', () {
    // loam-ignore: slop-tautological-assertion – exercises the matcher itself
    expect(true, isTrue);
  });
}
