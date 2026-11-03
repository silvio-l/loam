/// Code under test.
class Counter {
  int value = 0;

  void increment() => value++;

  void reset() {
    value = 0;
  }
}

/// Production helper that throws as part of its normal behaviour.
void strictIncrement(Counter c) {
  if (c.value > 100) throw StateError('too big');
  c.increment();
}
