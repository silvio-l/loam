/// File alpha — contains exact duplicates and unique code.
library;

/// An exact-duplicate block that also appears in beta.dart.
/// This is large enough to exceed the minimum token threshold.
///
/// Collector should find this as a cluster with a location in alpha.dart
/// and a corresponding location in beta.dart.
int computeTotal(List<int> values) {
  if (values.isEmpty) {
    return 0;
  }
  var total = 0;
  for (final value in values) {
    if (value > 0) {
      total = total + value;
    }
  }
  if (total < 0) {
    total = 0;
  }
  return total;
}

/// A block with renamed identifiers — structurally identical to
/// [processItems] in beta.dart but with different names.
/// This is a Type-2 duplicate.
String formatOutput(List<String> items) {
  if (items.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  for (final item in items) {
    if (item.isNotEmpty) {
      buffer.write(item);
      buffer.write(', ');
    }
  }
  final result = buffer.toString();
  return result;
}

/// A short block — below the minimum token threshold.
/// Should NOT be clustered even if identical elsewhere.
int addTwo(int a, int b) => a + b;

/// Unique code — no duplicate anywhere.
/// Should NOT appear in any cluster.
double computeAverage(List<double> numbers) {
  if (numbers.isEmpty) return 0.0;
  var sum = 0.0;
  for (final n in numbers) {
    sum += n;
  }
  return sum / numbers.length;
}
