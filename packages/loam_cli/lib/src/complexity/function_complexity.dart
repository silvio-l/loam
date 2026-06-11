import 'complexity_metrics.dart';

/// An immutable value object representing the complexity measurement of a
/// single named executable (top-level function, method, constructor, or
/// non-trivial getter/setter).
///
/// Produced by [FunctionComplexityCollector]. Acts as the shared data source
/// for the complexity rule and the health-score module — both consume the same
/// [FunctionComplexityCollector] output, ensuring no drift between the numbers.
///
/// Equality is value-based on all four fields.
final class FunctionComplexity {
  /// Creates a [FunctionComplexity].
  const FunctionComplexity({
    required this.qualifiedName,
    required this.filePath,
    required this.line,
    required this.metrics,
    this.isFlutterBuild = false,
  });

  /// Stable qualified symbol key.
  ///
  /// Format:
  /// - Top-level function: `functionName`
  /// - Named method / getter / setter: `ClassName.memberName`
  /// - Named constructor: `ClassName.constructorName`
  /// - Unnamed constructor: `ClassName.new`
  ///
  /// Used as the `semanticAnchor` for fingerprinting.
  final String qualifiedName;

  /// POSIX path relative to the project root.
  final String filePath;

  /// 1-based line number of the declaration.
  final int line;

  /// The complexity metrics for this executable.
  final ComplexityMetrics metrics;

  /// `true` when this executable is a Flutter widget-tree build method
  /// (`Widget build(...)` / `PreferredSizeWidget build(...)`).
  ///
  /// Such methods accrue cyclomatic/cognitive complexity from the declarative
  /// widget tree itself, not from branching business logic. The distinction
  /// drives the complexity finding's `kind` so an agent cannot conflate a large
  /// widget tree with a "god function" (or dismiss real logic as "just build").
  final bool isFlutterBuild;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionComplexity &&
          other.qualifiedName == qualifiedName &&
          other.filePath == filePath &&
          other.line == line &&
          other.metrics == metrics &&
          other.isFlutterBuild == isFlutterBuild;

  @override
  int get hashCode =>
      Object.hash(qualifiedName, filePath, line, metrics, isFlutterBuild);

  @override
  String toString() =>
      'FunctionComplexity('
      'qualifiedName: $qualifiedName, '
      'filePath: $filePath, '
      'line: $line, '
      'metrics: $metrics, '
      'isFlutterBuild: $isFlutterBuild)';
}
