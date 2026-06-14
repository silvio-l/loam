/// zeta — Type-2 clone (AC5).
///
/// [decodeAsDouble] is a Type-2 clone of [decodeAsBool] in epsilon.dart. The
/// identifier names and one error-message literal differ, but the
/// slot-repetition pattern is identical. Under consistent renaming both bodies
/// produce the same normalised sequence and MUST form a cluster.
library;

/// Decodes a raw map value as [double].
///
/// Raises [FormatException] when the value is absent or cannot be coerced.
/// The last error message distinguishes this function from its Type-2 twin
/// in epsilon.dart; all structural patterns remain the same.
dynamic decodeAsDouble(Map<String, dynamic> data, String field) {
  final value = data[field];
  if (value == null) throw FormatException('Missing value');
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is double) return value != 0.0;
  throw FormatException('AsDouble: unexpected type');
}
