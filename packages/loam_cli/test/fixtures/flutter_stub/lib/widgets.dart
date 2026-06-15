/// Minimal stubs of Flutter widgets for loam.dev test fixtures.
///
/// Only the named parameters relevant to the accessibility rules are included.
/// All positional parameters are typed as [Object?] to avoid importing
/// anything from the Flutter framework.
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

/// Stub of Flutter's `Icon` widget.
///
/// Used by the `a11y-icon-button-label` rule to detect pure-icon children of
/// interactive widgets ([GestureDetector], [InkWell]).
class Icon {
  /// Creates an [Icon].
  const Icon(this.icon);

  /// The icon data (e.g. an `IconData` instance in real Flutter).
  final Object? icon;
}

/// Stub of Flutter's `IconButton` widget.
///
/// The loam.dev `a11y-icon-button-label` rule checks that every instantiation
/// either carries a [tooltip] (accessible label for assistive technologies) or
/// is enclosed in a [Semantics] widget with a non-null [Semantics.label].
class IconButton {
  /// Creates an [IconButton].
  const IconButton({required this.icon, this.onPressed, this.tooltip});

  /// The icon to display inside the button.
  final Object icon;

  /// Called when the button is tapped or activated.
  final void Function()? onPressed;

  /// Text displayed in a tooltip and used as the accessible label.
  ///
  /// When non-null, screen readers announce this text for the button.
  final String? tooltip;
}

/// Stub of Flutter's `GestureDetector` widget.
///
/// The loam.dev `a11y-icon-button-label` rule flags a [GestureDetector] whose
/// [child] resolves to a pure [Icon] and that is not enclosed in a [Semantics]
/// widget with a non-null [Semantics.label].
class GestureDetector {
  /// Creates a [GestureDetector].
  const GestureDetector({this.child, this.onTap});

  /// The widget subtree to detect gestures on.
  final Object? child;

  /// Called when a tap occurs.
  final void Function()? onTap;
}

/// Stub of Flutter's `InkWell` widget.
///
/// The loam.dev `a11y-icon-button-label` rule flags an [InkWell] whose [child]
/// resolves to a pure [Icon] and that is not enclosed in a [Semantics] widget
/// with a non-null [Semantics.label].
class InkWell {
  /// Creates an [InkWell].
  const InkWell({this.child, this.onTap});

  /// The widget subtree that receives ink splashes.
  final Object? child;

  /// Called when a tap occurs.
  final void Function()? onTap;
}

/// Stub of Flutter's `Semantics` widget.
///
/// When [label] is non-null, this widget provides an accessible name to
/// assistive technologies for its [child] subtree. The loam.dev
/// `a11y-icon-button-label` rule treats any [Semantics] ancestor with a
/// non-null [label] as a sufficient accessible-name source.
class Semantics {
  /// Creates a [Semantics] widget.
  const Semantics({this.label, this.child});

  /// A textual description of the widget subtree for accessibility.
  final String? label;

  /// The widget below this widget in the tree.
  final Object? child;
}
