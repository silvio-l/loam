// GENERATED CODE — DO NOT EDIT BY HAND
// ignore_for_file: type=lint

/// Generated file — must be excluded by DuplicateCodeCollector.
/// Contains a copy of the duplicate block that appears in alpha.dart and
/// beta.dart; because this is a generated file it must NOT contribute to
/// any cluster.
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
