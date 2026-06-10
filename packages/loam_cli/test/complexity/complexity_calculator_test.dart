@TestOn('vm')
library;

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:loam/src/complexity/complexity_calculator.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helper: parse a Dart snippet and return the body of the first top-level
// function declaration named `f`.
// ---------------------------------------------------------------------------

FunctionBody _bodyOf(String source) {
  final result = parseString(
    content: source,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: true,
  );
  final decl = result.unit.declarations
      .whereType<FunctionDeclaration>()
      .firstWhere((d) => d.name.lexeme == 'f');
  return decl.functionExpression.body;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  const calc = ComplexityCalculator();

  // -------------------------------------------------------------------------
  // AC1: ComplexityMetrics is an immutable value object
  // -------------------------------------------------------------------------

  group('ComplexityMetrics value object', () {
    test('equality is value-based', () {
      const a = ComplexityMetrics(cyclomatic: 3, cognitive: 2);
      const b = ComplexityMetrics(cyclomatic: 3, cognitive: 2);
      const c = ComplexityMetrics(cyclomatic: 3, cognitive: 5);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is consistent with equality', () {
      const a = ComplexityMetrics(cyclomatic: 3, cognitive: 2);
      const b = ComplexityMetrics(cyclomatic: 3, cognitive: 2);
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString is deterministic', () {
      const m = ComplexityMetrics(cyclomatic: 4, cognitive: 7);
      expect(m.toString(), 'ComplexityMetrics(cyclomatic: 4, cognitive: 7)');
      expect(m.toString(), m.toString());
    });
  });

  // -------------------------------------------------------------------------
  // AC2 / AC4: Trivial function → cyclomatic == 1, cognitive == 0
  // -------------------------------------------------------------------------

  group('trivial functions', () {
    test('empty function body → cyclomatic:1, cognitive:0', () {
      final body = _bodyOf('void f() {}');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 1, cognitive: 0),
      );
    });

    test(
      'expression-body function without branching → cyclomatic:1, cognitive:0',
      () {
        final body = _bodyOf('int f() => 42;');
        expect(
          calc.calculate(body),
          ComplexityMetrics(cyclomatic: 1, cognitive: 0),
        );
      },
    );

    test('null body (abstract method) → cyclomatic:1, cognitive:0', () {
      expect(
        calc.calculate(null),
        ComplexityMetrics(cyclomatic: 1, cognitive: 0),
      );
    });

    test('EmptyFunctionBody → cyclomatic:1, cognitive:0', () {
      // Abstract method: the body is EmptyFunctionBody (a single semicolon).
      // Use a class context to get an abstract method.
      final result = parseString(
        content: 'abstract class C { void f(); }',
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: true,
      );
      final classDecl = result.unit.declarations
          .whereType<ClassDeclaration>()
          .first;
      final method = classDecl.body.members
          .whereType<MethodDeclaration>()
          .first;
      expect(
        calc.calculate(method.body),
        ComplexityMetrics(cyclomatic: 1, cognitive: 0),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC5: single `if`
  // -------------------------------------------------------------------------

  group('if statements', () {
    test('single if → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
void f(bool x) {
  if (x) {
    print(x);
  }
}
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });

    test('if/else → cyclomatic:2, cognitive:2', () {
      // if: +1 cyclo, +(1+0)=1 cognitive (nesting-aware at depth 0)
      // else: flat +1 cognitive (per cognitive complexity spec — no nesting
      // multiplier for else)
      final body = _bodyOf('''
void f(bool x) {
  if (x) {
    print(x);
  } else {
    print('no');
  }
}
''');
      // Cyclomatic: 1 (base) + 1 (if) = 2
      // Cognitive: 1 (if at depth 0) + 1 (else flat) = 2
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 2),
      );
    });

    test('if/else-if/else → cyclomatic:3, cognitive:3', () {
      // if:      +1 cyclo, +1 cognitive (nesting-aware at depth 0)
      // else-if: +1 cyclo, +1 cognitive (flat — continuation of if-chain)
      // else:    +0 cyclo, +1 cognitive (flat — continuation)
      final body = _bodyOf('''
void f(int x) {
  if (x > 0) {
    print('pos');
  } else if (x < 0) {
    print('neg');
  } else {
    print('zero');
  }
}
''');
      // Cyclomatic: 1 + 1 (if) + 1 (else-if) = 3
      // Cognitive: 1 (if) + 1 (else-if flat) + 1 (else flat) = 3
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 3),
      );
    });

    test('nested if — cognitive nesting-depth penalty visible', () {
      // Outer if: depth=0, cognitive += 1+0 = 1
      // Inner if: depth=1, cognitive += 1+1 = 2
      // Total cognitive = 3, cyclomatic = 1+2 = 3
      final body = _bodyOf('''
void f(bool a, bool b) {
  if (a) {
    if (b) {
      print('both');
    }
  }
}
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 3),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC5: for / while / do loops
  // -------------------------------------------------------------------------

  group('for loops', () {
    test('traditional for → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
void f(int n) {
  for (int i = 0; i < n; i++) {
    print(i);
  }
}
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });

    test('for-in → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
void f(List<int> items) {
  for (final x in items) {
    print(x);
  }
}
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });
  });

  group('while loop', () {
    test('while → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
void f(bool flag) {
  while (flag) {
    print(flag);
  }
}
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });
  });

  group('do-while loop', () {
    test('do-while → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
void f() {
  int i = 0;
  do {
    print(i);
    i++;
  } while (i < 5);
}
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC5: switch / case incl. pattern-when
  // -------------------------------------------------------------------------

  group('switch/case', () {
    test('switch with two cases → cyclomatic:3, cognitive:1', () {
      // switch itself: +1 cognitive (nesting-aware), depth += 1
      // case 1: +1 cyclo
      // case 2: +1 cyclo
      // default: +0 (it is the "else" path)
      // Total: cyclomatic = 1+2 = 3, cognitive = 1
      final body = _bodyOf('''
void f(int x) {
  switch (x) {
    case 1:
      print('one');
      break;
    case 2:
      print('two');
      break;
    default:
      print('other');
  }
}
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 1),
      );
    });

    test(
      'switch with pattern-when guard → cyclomatic incremented by guard',
      () {
        // SwitchPatternCase: +1 cyclo each (2 cases)
        // GuardedPattern with when: +1 cyclo, +1 cognitive each
        final body = _bodyOf('''
void f(Object x) {
  switch (x) {
    case int n when n > 0:
      print('positive');
    case String s when s.isNotEmpty:
      print('non-empty');
    default:
      print('other');
  }
}
''');
        // cyclo: 1 + 2 (SwitchPatternCase) + 2 (when guards) = 5
        // cognitive: 1 (switch nesting-aware) + 2 (when guards flat) = 3
        expect(
          calc.calculate(body),
          ComplexityMetrics(cyclomatic: 5, cognitive: 3),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC5: try/catch — multiple catch clauses
  // -------------------------------------------------------------------------

  group('try/catch', () {
    test('single catch → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
void f() {
  try {
    print('try');
  } catch (e) {
    print('catch');
  }
}
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });

    test('two catch clauses → cyclomatic:3, cognitive:2', () {
      // Use raw strings to avoid Dart string interpolation of `$e`.
      final body = _bodyOf(r'''
void f() {
  try {
    print('try');
  } on FormatException catch (e) {
    print(e);
  } catch (e) {
    print(e);
  }
}
''');
      // 2 catch clauses: +2 cyclo each, +2 cognitive (1+0 each, depth was 0
      // when each catch clause was entered)
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 2),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC5: logical operators && / || / ??
  // -------------------------------------------------------------------------

  group('logical operators', () {
    test('single && → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
bool f(bool a, bool b) => a && b;
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });

    test('single || → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
bool f(bool a, bool b) => a || b;
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });

    test('a && b && c — same-type chain counts once in cognitive', () {
      // `a && b && c` is `(a && b) && c` in the AST.
      // Outer &&: differs from parent (no parent &&) → cognitive +1
      // Inner `a && b`: right operand of outer && with same op → continuation
      //   → cognitive +0
      // Cyclomatic: +1 for each && token = +2
      final body = _bodyOf('''
bool f(bool a, bool b, bool c) => a && b && c;
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 1),
      );
    });

    test('a && b || c — operator switch adds extra cognitive point', () {
      // AST: `(a && b) || c`
      // ||: top-level, parent is not a logical op → cognitive +1
      // &&: right operand `a && b`, parent is || (different) → cognitive +1
      // Cyclomatic: +1 (||) + +1 (&&) = +2
      final body = _bodyOf('''
bool f(bool a, bool b, bool c) => a && b || c;
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 2),
      );
    });

    test('?? operator → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
String f(String? x) => x ?? "default";
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });

    test('multiple ?? in chain → cyclomatic:3, cognitive:2', () {
      final body = _bodyOf('''
String f(String? a, String? b) => a ?? b ?? "default";
''');
      // Each ?? is counted independently: +2 cyclo, +2 cognitive
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 2),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC5: conditional expression ?:
  // -------------------------------------------------------------------------

  group('conditional expression', () {
    test('ternary ?: → cyclomatic:2, cognitive:1', () {
      final body = _bodyOf('''
int f(bool x) => x ? 1 : 2;
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
    });

    test('nested ternary → cyclomatic:3, cognitive:2', () {
      final body = _bodyOf('''
int f(int x) => x > 0 ? 1 : (x < 0 ? -1 : 0);
''');
      // Two conditional expressions: +2 cyclo, +2 cognitive (flat, no nesting)
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 2),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC5: combination tests
  // -------------------------------------------------------------------------

  group('combinations', () {
    test('if + for loop + && → cyclomatic:4, cognitive:4', () {
      // if (depth 0): +1 cyclo, +1 cognitive
      //   for (depth 1): +1 cyclo, +2 cognitive
      //     && (flat): +1 cyclo, +1 cognitive
      final body = _bodyOf('''
void f(bool flag, List<int> items) {
  if (flag) {
    for (final x in items) {
      if (x > 0 && x < 100) {
        print(x);
      }
    }
  }
}
''');
      // if outer: cyclo+1, cog+(1+0)=1
      // for: cyclo+1, cog+(1+1)=2
      // if inner: cyclo+1, cog+(1+2)=3
      // &&: cyclo+1, cog+1 (flat)
      // total cyclo: 1+4=5, cognitive: 1+2+3+1=7
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 5, cognitive: 7),
      );
    });

    test('switch + catch in nested try → cyclomatic counts both', () {
      final body = _bodyOf('''
void f(int x) {
  switch (x) {
    case 1:
      try {
        print(x);
      } catch (e) {
        print(e);
      }
      break;
    default:
      print('other');
  }
}
''');
      // switch cognitive: +1 (depth 0), enters depth 1
      // case 1: +1 cyclo
      // catch: +1 cyclo, cognitive += 1+1=2 (depth 1)
      // Total: cyclo = 1+1+1=3, cognitive = 1+2=3
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 3),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC6: Determinism test — same input twice ⇒ identical result
  // -------------------------------------------------------------------------

  group('determinism', () {
    test('same body parsed twice yields identical ComplexityMetrics', () {
      const source = '''
void f(bool a, bool b, List<int> items) {
  if (a && b) {
    for (final x in items) {
      if (x > 0) {
        print(x);
      } else {
        print('neg');
      }
    }
  }
}
''';
      final body1 = _bodyOf(source);
      final body2 = _bodyOf(source);
      final result1 = calc.calculate(body1);
      final result2 = calc.calculate(body2);
      expect(result1, equals(result2));
      expect(result1.cyclomatic, equals(result2.cyclomatic));
      expect(result1.cognitive, equals(result2.cognitive));
    });

    test(
      'two calculator instances on the same body yield identical result',
      () {
        final body = _bodyOf('''
void f(int x) {
  if (x > 0) {
    while (x > 1) {
      x--;
    }
  }
}
''');
        const calc2 = ComplexityCalculator();
        expect(calc.calculate(body), equals(calc2.calculate(body)));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Closure / local function — depth reset, counts flow into enclosing
  // -------------------------------------------------------------------------

  group('closures and local functions', () {
    test('closure inside if: closure nesting depth resets to 0', () {
      // if (depth 0): +1 cyclo, +1 cognitive
      // closure body has depth reset → if inside closure is at depth 0
      // inner if (depth 0 inside closure): +1 cyclo, +1 cognitive
      // Total: cyclo = 1+2=3, cognitive = 1+1=2
      final body = _bodyOf('''
void f(bool flag) {
  if (flag) {
    final fn = () {
      if (flag) print('inner');
    };
    fn();
  }
}
''');
      expect(
        calc.calculate(body),
        ComplexityMetrics(cyclomatic: 3, cognitive: 2),
      );
    });
  });
}
