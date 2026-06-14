/// gamma — parallel boilerplate A.
///
/// [computeWeightedSum] uses [value] in the arithmetic positions that differ
/// from [computeScaledSum] in delta.dart. Under consistent (alpha) renaming
/// the two bodies produce DIFFERENT slot-repetition patterns and must NOT
/// form a duplicate cluster.
library;

/// Computes a weighted sum that reuses the first parameter ([value]) at
/// positions that produce a distinct normalised pattern from delta.dart.
///
/// Pattern difference: this body contains `ID#0 * ID#0` (value squared) and
/// ends with `ID#2 + ID#0` (result + value), whereas delta.dart's corresponding
/// body contains `ID#0 * ID#1` and `ID#2 + ID#1`.
int computeWeightedSum(int value, int factor) {
  var result = value * factor + value;
  if (result < 0) {
    result = 0;
  }
  final squared = value * value;
  final combined = squared + result;
  if (combined > value * factor) {
    return combined;
  }
  final adjusted = result + value;
  return adjusted;
}
