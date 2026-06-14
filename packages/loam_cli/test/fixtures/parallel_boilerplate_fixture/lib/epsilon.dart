/// epsilon — Type-2 clone (AC5).
///
/// [decodeAsBool] is a Type-2 clone of [decodeAsDouble] in zeta.dart. The
/// identifier names and one error-message literal differ, but the
/// slot-repetition pattern is identical. Under consistent renaming both bodies
/// produce the same normalised sequence and MUST form a cluster.
library;

/// Decodes a raw map value as [bool].
///
/// Raises [FormatException] when the value is absent or cannot be coerced.
/// The last error message distinguishes this function from its Type-2 twin
/// in zeta.dart; all structural patterns remain the same.
dynamic decodeAsBool(Map<String, dynamic> row, String key) {
  final raw = row[key];
  if (raw == null) throw FormatException('Missing value');
  if (raw is bool) return raw;
  if (raw is int) return raw != 0;
  if (raw is double) return raw != 0.0;
  throw FormatException('AsBool: unexpected type');
}
