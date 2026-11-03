import 'package:test/test.dart';

int compute() => 42;
int next() => DateTime.now().microsecond;

class Row {
  const Row(this.id);
  final int id;
}

// Not the test framework's `expect`: a local helper with the same name.
void local(Object? a, Object? b) {}

void main() {
  final rows = [const Row(1), const Row(2)];
  final id = 7;

  test('real assertions', () {
    expect(compute(), 42);
    expect(compute() + 1, 43);
    expect(id, isTrue);
    expect(rows.length, equals(2));
    expect([for (final r in rows) r.id], [1, 2]);
    expect([id, 2], equals([id, 2]));
    expect((id, 'a'), (7, 'a'));
    expect('v$id', 'v7');
    expect(next(), next());
    expect(rows.first.hashCode, rows.first.hashCode);
    expect(rows.first.id, rows.last.id);
  });

  test('shadowed expect is not the framework one', () {
    void expect(Object? a, Object? b) {}
    expect(true, isTrue);
  });

  test('helper', () {
    local(true, true);
  });
}
