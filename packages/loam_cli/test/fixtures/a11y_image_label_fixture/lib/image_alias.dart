// Negative fixture: MyImage is NOT Flutter's Image → rule must NOT fire (AC3).
// The class is defined locally and has no relation to package:flutter.

/// A local image widget substitute — not Flutter's Image class.
class MyImage {
  /// Creates a [MyImage].
  const MyImage({this.semanticLabel, this.excludeFromSemantics = false});

  /// The semantic label.
  final String? semanticLabel;

  /// Whether to exclude from semantics.
  final bool excludeFromSemantics;

  /// Creates a [MyImage] from an asset path.
  static MyImage asset(String name) => const MyImage();
}

/// Uses a local MyImage class — rule must ignore this (not package:flutter).
Object buildAliasedImage() => MyImage.asset('assets/logo.png');

/// Unnamed MyImage — must not produce a finding.
Object buildAliasedUnnamed() => const MyImage();
