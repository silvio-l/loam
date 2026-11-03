import 'package:slop_assertion_free_test_fixture/counter.dart';
import 'package:test/test.dart';

void ping(Counter c, int n) => n > 0 ? pong(c, n - 1) : null;
void pong(Counter c, int n) => ping(c, n);

void main() {
  test('mutual recursion without an assertion is still flagged', () {
    ping(Counter(), 3);
  });
}
