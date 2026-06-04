import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Computes a position-robust, deterministic fingerprint for a [Finding].
///
/// The fingerprint is a 16-character lowercase hex string (64 bits of SHA-256).
/// It uniquely identifies a finding by its **semantic identity**, not its
/// presentation: line/column shifts and reformatting do not change the
/// fingerprint (see CONTEXT.md — "Fingerprint").
///
/// Inputs (concatenated with NUL separators before hashing):
/// 1. [ruleId] — the rule that produced the finding.
/// 2. [relativePath] — POSIX-normalised path relative to the project root.
///    Backslashes are defensively replaced with `/` before hashing.
/// 3. [semanticAnchor] — a caller-supplied stable symbol key
///    (e.g. `MyClass.foo`). The function does not derive or infer this value.
///
/// Not included: `severity`, `message`, `line`, `column`, absolute paths,
/// or ruleset version.
String computeFingerprint({
  required String ruleId,
  required String relativePath,
  required String semanticAnchor,
}) {
  // Defensive POSIX normalisation: replace every backslash with a forward slash.
  final posixPath = relativePath.replaceAll(r'\', '/');

  // Canonical concatenation with NUL separators avoids length-extension
  // confusion between adjacent fields.
  final canonical = '$ruleId\x00$posixPath\x00$semanticAnchor';

  final digest = sha256.convert(utf8.encode(canonical));

  // Truncate to 16 hex characters (64 bits) — sufficient collision resistance
  // for the baseline use-case within a single codebase.
  return digest.toString().substring(0, 16);
}
