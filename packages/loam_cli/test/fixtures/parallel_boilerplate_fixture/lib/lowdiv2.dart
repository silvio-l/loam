/// lowdiv2 — low-diversity block B (distinct-token-gate AC4).
///
/// [sumRepeatedB] is structurally identical to [sumRepeatedA] in lowdiv.dart
/// (only the parameter name differs — a Type-2 clone). Both have only 6
/// distinct normalised token strings and are filtered by the
/// distinct-token-gate before any clustering can occur. They must NOT form a
/// cluster.
library;

/// Returns the sum of [y] added to itself 25 times.
///
/// Intentionally repetitive: the normalised body contains only the token
/// strings `{`, `return`, `ID#0`, `+`, `;`, `}` — six distinct types, which
/// is below [kMinDistinctTokenTypes].
int sumRepeatedB(int y) {
  return y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y +
      y;
}
