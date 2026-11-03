import 'package:test/test.dart';

final x = DateTime.now().millisecond;

/// Holds a stored field.
class Holder {
  /// Creates a holder.
  Holder(this.value);

  /// The stored value.
  final int value;
}

final holder = Holder(3);

void main() {
  test('constant against constant', () {
    expect(true, isTrue); // flagged
    expect(1, 1); // flagged
    expect(null, isNull); // flagged
    expect(-2.5, equals(-2.5)); // flagged
    expect(
      'a'
      'b',
      isNotEmpty,
    ); // flagged
    expect(const [1, 2], equals([1, 2])); // flagged
  });

  test('value against itself', () {
    expect(x, x); // flagged
    expect(x, equals(x)); // flagged
    expect(holder.value, holder.value); // flagged
  });

  test('async variant', () async {
    await expectLater(false, isFalse); // flagged
  });
}
