/// Main library file for the complexity_collector_fixture.
/// Includes a part file to test no double-counting.
library;

part 'calculator_part.dart';

/// A trivial top-level function with no decision points.
/// Expected: cyclomatic=1, cognitive=0.
void topLevelSimple() {}

/// A top-level function with one branch.
/// Expected: cyclomatic=2, cognitive=1.
void topLevelWithBranch(bool x) {
  if (x) {
    print(x);
  }
}

/// A simple calculator class declared in the library file.
class Calculator {
  int _value = 0;

  /// Unnamed constructor with a non-trivial body.
  /// Expected: cyclomatic=1, cognitive=0.
  Calculator(int initial) {
    _value = initial;
  }

  /// Named constructor with a branch.
  /// Expected: cyclomatic=2, cognitive=1.
  Calculator.fromPositive(int initial) {
    if (initial > 0) {
      _value = initial;
    }
  }

  /// Simple method — no decision points.
  /// Expected: cyclomatic=1, cognitive=0.
  int add(int a, int b) => a + b;

  /// Method with if + while → cyclomatic=3, cognitive=2.
  int factorial(int n) {
    if (n < 0) return -1;
    int result = 1;
    while (n > 1) {
      result *= n--;
    }
    return result;
  }

  /// Getter with expression body — no decision points.
  /// Expected: cyclomatic=1, cognitive=0.
  int get value => _value;

  /// Setter with a branch.
  /// Expected: cyclomatic=2, cognitive=1.
  set value(int v) {
    if (v >= 0) {
      _value = v;
    }
  }
}
