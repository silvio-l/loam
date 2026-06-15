/// Minimal stub of Flutter's Image widget for loam.dev test fixtures.
///
/// Only the named parameters relevant to the `a11y-image-label` rule are
/// included — [semanticLabel] and [excludeFromSemantics]. All positional
/// parameters are typed as [Object?] to avoid importing anything from the
/// Flutter framework.
///
/// IMPORTANT: Named constructors (`Image.asset`, `Image.network`, `Image.file`,
/// `Image.memory`) are declared as **factory constructors** (not static methods)
/// to match Flutter's real API. This causes the Dart analyser to resolve
/// `Image.asset(...)` calls as `InstanceCreationExpression` nodes, which is
/// exactly what the `a11y-image-label` rule visits.
library;

/// Stub of Flutter's `Image` widget.
///
/// The loam.dev `a11y-image-label` rule checks that every instantiation of the
/// real Flutter `Image` class carries a [semanticLabel] or sets
/// [excludeFromSemantics] to `true`. This stub, located in a package named
/// `flutter`, lets test fixtures exercise that check using the resolved element
/// model (package URI `package:flutter/widgets.dart`) without depending on the
/// full Flutter SDK.
class Image {
  /// Unnamed constructor (mirrors Flutter's `Image(image: ...)` constructor).
  const Image({this.semanticLabel, this.excludeFromSemantics = false});

  /// The semantic label for this image.
  final String? semanticLabel;

  /// Whether to exclude this image from accessibility semantics.
  final bool excludeFromSemantics;

  /// Creates an Image from an asset bundle.
  ///
  /// Declared as a factory constructor (not a static method) to match
  /// Flutter's real API and produce `InstanceCreationExpression` AST nodes.
  factory Image.asset(
    String name, {
    String? semanticLabel,
    bool excludeFromSemantics = false,
  }) {
    return Image(
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
    );
  }

  /// Creates an Image that displays from a [String] URL.
  factory Image.network(
    String src, {
    String? semanticLabel,
    bool excludeFromSemantics = false,
  }) {
    return Image(
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
    );
  }

  /// Creates an Image from a file.
  factory Image.file(
    Object file, {
    String? semanticLabel,
    bool excludeFromSemantics = false,
  }) {
    return Image(
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
    );
  }

  /// Creates an Image from raw bytes.
  factory Image.memory(
    List<int> bytes, {
    String? semanticLabel,
    bool excludeFromSemantics = false,
  }) {
    return Image(
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
    );
  }
}
