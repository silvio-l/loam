/// delta — parallel boilerplate B.
///
/// [computeScaledSum] has the same structural skeleton as [computeWeightedSum]
/// in gamma.dart, but reuses the SECOND parameter ([scale]) where gamma reuses
/// the first. Under consistent (alpha) renaming the two bodies produce DIFFERENT
/// slot-repetition patterns and must NOT form a duplicate cluster.
library;

/// Computes a scaled sum that reuses the second parameter ([scale]) at
/// positions that produce a distinct normalised pattern from gamma.dart.
///
/// Pattern difference: this body contains `ID#0 * ID#1` (not squaring) and
/// ends with `ID#2 + ID#1` (result + scale), whereas gamma.dart's corresponding
/// body contains `ID#0 * ID#0` and `ID#2 + ID#0`.
int computeScaledSum(int base, int scale) {
  var result = base * scale + scale;
  if (result < 0) {
    result = 0;
  }
  final squared = base * scale;
  final combined = squared + result;
  if (combined > base * scale) {
    return combined;
  }
  final adjusted = result + scale;
  return adjusted;
}
