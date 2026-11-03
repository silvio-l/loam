import 'package:slop_assertion_free_test_fixture/counter.dart';
import 'package:test/test.dart';

/// Not an assertion for loam until it is listed under
/// `slop_assertion_free_test.assertion_functions`.
void assertHealthy(Counter c) {
  if (c.value < 0) c.reset();
}

void main() {
  test('uses a project assertion helper', () {
    assertHealthy(Counter());
  });
}
