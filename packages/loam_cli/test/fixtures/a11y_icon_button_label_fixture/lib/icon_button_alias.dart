// Negative fixture (AC4 — alias/codegen counter-example):
// Local class named IconButton that is NOT package:flutter — rule must NOT fire.
// Verifies Invariant 1: element model, not name matching.

/// A locally-defined button widget — not Flutter's IconButton class.
/// The loam.dev rule uses the resolved element model; it must ignore this.
class IconButton {
  /// Creates a local [IconButton].
  const IconButton({this.icon, this.onPressed, this.tooltip});

  /// The icon widget.
  final Object? icon;

  /// Callback.
  final void Function()? onPressed;

  /// Tooltip text.
  final String? tooltip;
}

/// Instantiation of the local (non-Flutter) IconButton — zero findings expected.
Object buildAliasedButton() => const IconButton(icon: null);
