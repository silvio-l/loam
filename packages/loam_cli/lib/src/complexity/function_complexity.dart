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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FunctionComplexity &&
          other.qualifiedName == qualifiedName &&
          other.filePath == filePath &&
          other.line == line &&
          other.metrics == metrics;

  @override
  int get hashCode => Object.hash(qualifiedName, filePath, line, metrics);

  @override
  String toString() =>
      'FunctionComplexity('
      'qualifiedName: $qualifiedName, '
      'filePath: $filePath, '
      'line: $line, '
      'metrics: $metrics)';
}
