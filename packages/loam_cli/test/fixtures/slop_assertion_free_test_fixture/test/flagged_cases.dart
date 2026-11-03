import 'package:slop_assertion_free_test_fixture/counter.dart';
import 'package:test/test.dart';

/// Runs the counter but checks nothing — not an assertion helper.
void runOnly(Counter c) {
  c.increment();
  helperTwo(c);
}

void helperTwo(Counter c) => c.reset();

void main() {
  group('counter', () {
    test('increments the value', () {
      final c = Counter();
      c.increment();
    });

    test('has only a comment', () {
      // TODO: assert something
    });

    test('goes through a helper that never asserts', () {
      runOnly(Counter());
    });

    test('calls production code that throws on its own', () {
      strictIncrement(Counter());
    });

    test('skip false is still a test', skip: false, () {
      Counter().increment();
    });

    test('too deep', () {
      deepOne(Counter());
    });

    // Same description twice in one scope: told apart by order.
    test('duplicate', () {
      Counter().increment();
    });
    test('duplicate', () {
      Counter().increment();
    });
  });
}

void deepOne(Counter c) => deepTwo(c);
void deepTwo(Counter c) => deepThree(c);
void deepThree(Counter c) => deepFour(c);
void deepFour(Counter c) => expect(c.value, 0);
