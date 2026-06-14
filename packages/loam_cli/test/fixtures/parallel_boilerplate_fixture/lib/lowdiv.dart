/// lowdiv — low-diversity block A (distinct-token-gate AC4).
///
/// [sumRepeatedA] has more than [kMinDuplicateTokens] tokens but only 6
/// distinct normalised token strings. It must be filtered by the
/// distinct-token-gate ([kMinDistinctTokenTypes] = 8) and must NOT form a
/// cluster with [sumRepeatedB] in lowdiv2.dart — even though consistent
/// renaming would produce the same pattern for both.
library;

/// Returns the sum of [x] added to itself 25 times.
///
/// Intentionally repetitive: the normalised body contains only the token
/// strings `{`, `return`, `ID#0`, `+`, `;`, `}` — six distinct types, which
/// is below [kMinDistinctTokenTypes].
int sumRepeatedA(int x) {
  return x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x +
      x;
}
