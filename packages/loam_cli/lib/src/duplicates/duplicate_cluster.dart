/// Data model types produced by [DuplicateCodeCollector].
library;

/// The minimum number of normalised tokens a code block must contain before
/// it is considered a duplicate candidate.
///
/// Conservative default: 50 tokens correspond roughly to 5–10 non-trivial
/// statements. Setting the threshold this high prevents one- and two-liner
/// helpers (e.g. `int add(int a, int b) => a + b;`) from generating noise.
/// The PRD explicitly asks to err on the high side — a missed duplicate
/// (false negative) is better than a flood of false positives that erode
/// trust in the tool.
const int kMinDuplicateTokens = 50;

/// A single source location within a [DuplicateCluster].
///
/// Identifies a contiguous range of code (start line – end line) inside
/// a single file that shares its normalised token sequence with at least
/// one other [DuplicateLocation] in the same cluster.
final class DuplicateLocation {
  /// Creates a [DuplicateLocation].
  const DuplicateLocation({
    required this.filePath,
    required this.startLine,
    required this.endLine,
  });

  /// POSIX path of the file, relative to the project root.
  final String filePath;

  /// 1-based line number of the first token of this block.
  final int startLine;

  /// 1-based line number of the last token of this block.
  final int endLine;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DuplicateLocation &&
          other.filePath == filePath &&
          other.startLine == startLine &&
          other.endLine == endLine;

  @override
  int get hashCode => Object.hash(filePath, startLine, endLine);

  @override
  String toString() =>
      'DuplicateLocation(filePath: $filePath, '
      'startLine: $startLine, endLine: $endLine)';
}

/// A cluster of code locations that share the same normalised token sequence.
///
/// Every cluster contains at least two [DuplicateLocation]s — a single
/// occurrence is never reported. The [locations] list is sorted
/// lexicographically (filePath → startLine) so that the first element is
/// always the stable anchor used for fingerprinting.
final class DuplicateCluster {
  /// Creates a [DuplicateCluster].
  const DuplicateCluster({required this.locations, required this.tokenCount});

  /// All occurrences of the duplicated block, sorted by filePath → startLine.
  ///
  /// Contains at least two elements.
  final List<DuplicateLocation> locations;

  /// Number of normalised tokens in the duplicated block.
  ///
  /// Always ≥ [kMinDuplicateTokens].
  final int tokenCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DuplicateCluster &&
          other.tokenCount == tokenCount &&
          _listEquals(other.locations, locations);

  @override
  int get hashCode => Object.hashAll([tokenCount, ...locations]);

  @override
  String toString() =>
      'DuplicateCluster(tokenCount: $tokenCount, locations: $locations)';

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
