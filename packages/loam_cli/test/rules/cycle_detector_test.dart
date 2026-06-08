import 'package:loam/src/rules/cycle_detector.dart';
import 'package:test/test.dart';

void main() {
  late CycleDetector detector;

  setUp(() => detector = CycleDetector());

  // ---------------------------------------------------------------------------
  // AC: empty graph and pure DAG → no SCCs
  // ---------------------------------------------------------------------------

  test('empty graph returns no SCCs', () {
    expect(detector.findCycles({}), isEmpty);
  });

  test('single node with no edges returns no SCCs', () {
    expect(detector.findCycles({'a': {}}), isEmpty);
  });

  test('pure DAG returns no SCCs', () {
    // a → b → c  (no back-edge)
    final graph = {
      'a': {'b'},
      'b': {'c'},
      'c': <String>{},
    };
    expect(detector.findCycles(graph), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // AC: self-loop is NOT reported as a cluster
  // ---------------------------------------------------------------------------

  test('self-loop is not reported as a non-trivial SCC', () {
    final graph = {
      'a': {'a'},
    };
    expect(detector.findCycles(graph), isEmpty);
  });

  test('self-loop combined with a DAG edge is not reported', () {
    final graph = {
      'a': {'a', 'b'},
      'b': <String>{},
    };
    expect(detector.findCycles(graph), isEmpty);
  });

  // ---------------------------------------------------------------------------
  // AC: simple 2-node cycle → one cluster
  // ---------------------------------------------------------------------------

  test('2-node cycle yields one SCC with both members', () {
    final graph = {
      'a': {'b'},
      'b': {'a'},
    };
    final sccs = detector.findCycles(graph);
    expect(sccs, hasLength(1));
    expect(sccs.first, equals(['a', 'b']));
  });

  // ---------------------------------------------------------------------------
  // AC: 3-node ring → one cluster
  // ---------------------------------------------------------------------------

  test('3-node ring yields one SCC with all three members', () {
    final graph = {
      'a': {'b'},
      'b': {'c'},
      'c': {'a'},
    };
    final sccs = detector.findCycles(graph);
    expect(sccs, hasLength(1));
    expect(sccs.first, equals(['a', 'b', 'c']));
  });

  // ---------------------------------------------------------------------------
  // AC: two disjoint cycles → two clusters
  // ---------------------------------------------------------------------------

  test('two disjoint 2-node cycles yield two SCCs', () {
    final graph = {
      'a': {'b'},
      'b': {'a'},
      'c': {'d'},
      'd': {'c'},
    };
    final sccs = detector.findCycles(graph);
    expect(sccs, hasLength(2));
    expect(sccs[0], equals(['a', 'b']));
    expect(sccs[1], equals(['c', 'd']));
  });

  // ---------------------------------------------------------------------------
  // AC: overlapping/nested cycles that form one SCC → one cluster
  // ---------------------------------------------------------------------------

  test('two overlapping cycles that share nodes form one SCC', () {
    // a→b→c→a and a→b→d→a: all of {a,b,c,d} are mutually reachable → 1 SCC.
    final graph = {
      'a': {'b'},
      'b': {'c', 'd'},
      'c': {'a'},
      'd': {'a'},
    };
    final sccs = detector.findCycles(graph);
    expect(sccs, hasLength(1));
    expect(sccs.first, equals(['a', 'b', 'c', 'd']));
  });

  test('nested cycles within a larger cycle form one SCC', () {
    // a→b→c→a forms a ring; b→d→b adds an inner 2-cycle.
    // All nodes {a,b,c,d} are mutually reachable.
    final graph = {
      'a': {'b'},
      'b': {'c', 'd'},
      'c': {'a'},
      'd': {'b'},
    };
    final sccs = detector.findCycles(graph);
    expect(sccs, hasLength(1));
    expect(sccs.first, equals(['a', 'b', 'c', 'd']));
  });

  // ---------------------------------------------------------------------------
  // AC: determinism — insertion order must not affect output
  // ---------------------------------------------------------------------------

  test('output is identical regardless of insertion order', () {
    final graph1 = {
      'c': {'d'},
      'd': {'c'},
      'a': {'b'},
      'b': {'a'},
    };
    final graph2 = {
      'a': {'b'},
      'b': {'a'},
      'c': {'d'},
      'd': {'c'},
    };
    final result1 = detector.findCycles(graph1);
    final result2 = detector.findCycles(graph2);
    expect(result1, equals(result2));
  });

  test('SCC members are sorted alphabetically', () {
    // Insert in reverse order to verify sorting.
    final graph = {
      'z': {'y'},
      'y': {'x'},
      'x': {'z'},
    };
    final sccs = detector.findCycles(graph);
    expect(sccs, hasLength(1));
    expect(sccs.first, equals(['x', 'y', 'z']));
  });

  test('SCC list is sorted by smallest member', () {
    // Cycle 1: {p, q}, cycle 2: {m, n} → list should be [{m,n},{p,q}]
    final graph = {
      'p': {'q'},
      'q': {'p'},
      'm': {'n'},
      'n': {'m'},
    };
    final sccs = detector.findCycles(graph);
    expect(sccs, hasLength(2));
    expect(sccs[0].first, equals('m'));
    expect(sccs[1].first, equals('p'));
  });

  // ---------------------------------------------------------------------------
  // AC: pure-target nodes (appear only as edge targets) handled gracefully
  // ---------------------------------------------------------------------------

  test('node appearing only as target with no back-edge is not in an SCC', () {
    // a→b→c: b appears as a target of a; c appears only as target of b.
    final graph = {
      'a': {'b'},
      'b': {'c'},
    };
    expect(detector.findCycles(graph), isEmpty);
  });
}
