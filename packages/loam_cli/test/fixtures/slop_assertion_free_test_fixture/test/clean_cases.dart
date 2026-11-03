import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:slop_assertion_free_test_fixture/counter.dart';
import 'package:test/test.dart';

class MockCounter extends Mock implements Counter {}

void checkValue(Counter c, int expected) {
  expect(c.value, expected);
}

void middle(Counter c) => checkValue(c, 0);

void top(Counter c) => middle(c);

/// Wrapper: the checks live in the callback supplied at each call site.
void wrapped(String description, void Function(Counter) body) {
  test(description, () {
    body(Counter());
  });
}

class _Case {
  _Case(this.check);
  final void Function(Counter) check;
}

void main() {
  wrapped('wrapper delegating to a callback', (c) => expect(c.value, 0));

  test('callback stored in a field', () {
    final c = _Case((counter) => expect(counter.value, 0));
    c.check(Counter());
  });

  test('direct expect', () {
    final c = Counter()..increment();
    expect(c.value, 1);
  });

  test('helper that asserts', () {
    checkValue(Counter(), 0);
  });

  test('helper three hops away', () {
    top(Counter());
  });

  test('expectLater with a stream', () async {
    final controller = StreamController<int>();
    controller.add(1);
    await expectLater(controller.stream, emits(1));
  });

  test('verify on a mock', () {
    final mock = MockCounter();
    mock.increment();
    verify(mock.increment).called(1);
  });

  test('verifyNever on a mock', () {
    final mock = MockCounter();
    verifyNever(mock.reset);
  });

  test('explicit fail', () {
    if (Counter().value != 0) fail('not zero');
  });

  test('expectAsync callback', () {
    final done = expectAsync0(() {});
    done();
  });

  test('hand-written throw', () {
    if (Counter().value != 0) throw StateError('not zero');
  });

  test('assertion inside a closure passed on', () {
    void run(void Function() body) => body();
    run(() => expect(Counter().value, 0));
  });

  test('body is a project function that asserts', _namedBody);

  test('skipped with a reason', skip: 'flaky on CI', () {
    Counter().increment();
  });

  test('skipped by condition', skip: 1 > 2, () {
    Counter().increment();
  });

  // loam-ignore: slop-assertion-free-test – smoke test, does-not-throw is the point
  test('suppressed on purpose', () {
    Counter().increment();
  });
}

void _namedBody() {
  expect(1 + 1, 2);
}
