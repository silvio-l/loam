/// A **Boundary**: a forbidden edge between **Layers** (internal-notes).
///
/// Layers are a name -> project-relative directory prefix map (e.g.
/// `core` -> `lib/core`) in `loam.yaml` (`layers:`); boundaries
/// (`boundaries:`) list, per importing layer, the layers it must not import.
/// The boundary-violation rule reads exactly this - it never re-detects.
class LayerBoundary {
  /// Creates a boundary: files of layer [from] must not import files of any
  /// layer in [deny].
  const LayerBoundary({required this.from, required this.deny});

  /// The importing layer.
  final String from;

  /// Layers [from] must not depend on (forbidden edges).
  final List<String> deny;

  @override
  bool operator ==(Object other) =>
      other is LayerBoundary &&
      other.from == from &&
      other.deny.length == deny.length &&
      Iterable<int>.generate(
        deny.length,
      ).every((i) => deny[i] == other.deny[i]);

  @override
  int get hashCode => Object.hash(from, Object.hashAll(deny));

  @override
  String toString() => 'LayerBoundary($from -> ${deny.join(', ')})';
}
