/// File beta — contains exact duplicates and Type-2 duplicates.
library;

/// Exact duplicate of [computeTotal] in alpha.dart (Type-1).
/// The normalized token sequence is identical — should form a cluster.
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

/// Type-2 duplicate of [formatOutput] in alpha.dart.
/// All identifier names and literals differ, but the structure is identical.
String processItems(List<String> elements) {
  if (elements.isEmpty) {
    return '';
  }
  final buf = StringBuffer();
  for (final el in elements) {
    if (el.isNotEmpty) {
      buf.write(el);
      buf.write(', ');
    }
  }
  final output = buf.toString();
  return output;
}

/// A short block — below the minimum token threshold.
/// Not clustered even if identical to addTwo in alpha.dart.
int addTwo(int a, int b) => a + b;

/// Unique code — structurally different from everything else.
/// Verifies no false positives from the collector.
bool isValidEmail(String email) {
  final atIndex = email.indexOf('@');
  if (atIndex < 1) return false;
  final domainPart = email.substring(atIndex + 1);
  if (domainPart.isEmpty) return false;
  final dotIndex = domainPart.lastIndexOf('.');
  return dotIndex > 0 && dotIndex < domainPart.length - 1;
}
