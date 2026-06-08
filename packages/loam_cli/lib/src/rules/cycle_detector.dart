/// Tarjan SCC detector over an abstract directed graph with opaque node keys.
///
/// Finds all non-trivial strongly connected components (SCCs with ≥ 2 members).
/// Self-loops (a node pointing to itself) are NOT reported as non-trivial.
///
/// Output is deterministic (Invariant 5):
/// - Members within each SCC are sorted.
/// - The SCC list is sorted by each SCC's smallest member.
/// - Tarjan traversal iterates over sorted adjacency lists so results are
///   independent of the hash-iteration order of the input map.
///
/// No `package:analyzer` dependency — purely algorithmic, testable with
/// synthetic graphs.
class CycleDetector {
  /// Finds non-trivial SCCs in [graph].
  ///
  /// [graph] maps each node key to the set of keys it has outgoing edges to.
  /// Nodes that appear only as edge targets (not as keys) are treated as having
  /// no outgoing edges.
  ///
  /// Returns a list of SCCs, each represented as a sorted list of member keys.
  /// The list itself is sorted by each SCC's smallest member key.
  /// Returns an empty list if the graph is acyclic or empty.
  List<List<String>> findCycles(Map<String, Set<String>> graph) {
    // Collect all nodes (sources + pure targets) and sort for determinism.
    final allNodes = <String>{};
    for (final entry in graph.entries) {
      allNodes.add(entry.key);
      allNodes.addAll(entry.value);
    }
    final sortedNodes = allNodes.toList()..sort();

    // Tarjan state.
    var index = 0;
    final indices = <String, int>{};
    final lowlinks = <String, int>{};
    final onStack = <String, bool>{};
    final stack = <String>[];
    final sccs = <List<String>>[];

    void strongConnect(String v) {
      indices[v] = index;
      lowlinks[v] = index;
      index++;
      stack.add(v);
      onStack[v] = true;

      // Iterate over sorted neighbours for determinism.
      final neighbours = (graph[v] ?? <String>{}).toList()..sort();
      for (final w in neighbours) {
        if (!indices.containsKey(w)) {
          strongConnect(w);
          lowlinks[v] = lowlinks[v]! < lowlinks[w]!
              ? lowlinks[v]!
              : lowlinks[w]!;
        } else if (onStack[w] == true) {
          lowlinks[v] = lowlinks[v]! < indices[w]! ? lowlinks[v]! : indices[w]!;
        }
      }

      // If v is a root of an SCC, pop the stack.
      if (lowlinks[v] == indices[v]) {
        final scc = <String>[];
        String w;
        do {
          w = stack.removeLast();
          onStack[w] = false;
          scc.add(w);
        } while (w != v);

        // Only report non-trivial SCCs (≥ 2 members).
        if (scc.length >= 2) {
          scc.sort();
          sccs.add(scc);
        }
      }
    }

    for (final node in sortedNodes) {
      if (!indices.containsKey(node)) {
        strongConnect(node);
      }
    }

    // Sort SCCs by their smallest member for deterministic output.
    sccs.sort((a, b) => a.first.compareTo(b.first));
    return sccs;
  }
}
