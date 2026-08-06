/// Negative fixture for `a11y-interactive-semantics`.
///
/// Covers the `semanticLabel:` and `tooltip:` variants of the call-site
/// accessible-name-property check, in addition to `label:` (covered by
/// `label_property_self_wrapped_clean.dart` and
/// `label_property_delegating_clean.dart`).
library;

/// A custom widget exposing all three recognised accessible-name arguments
/// as optional properties.
class AnnotatedWidget {
  /// Creates an [AnnotatedWidget].
  const AnnotatedWidget({
    required this.onTap,
    this.label,
    this.semanticLabel,
    this.tooltip,
  });

  /// Called when the widget is tapped.
  final void Function() onTap;

  /// Accessible name via `label`.
  final String? label;

  /// Accessible name via `semanticLabel`.
  final String? semanticLabel;

  /// Accessible name via `tooltip`.
  final String? tooltip;
}

/// Negative case: `semanticLabel:` alone is sufficient.
Object buildWithSemanticLabel() =>
    AnnotatedWidget(onTap: () {}, semanticLabel: 'Delete item');

/// Negative case: `tooltip:` alone is sufficient.
Object buildWithTooltip() =>
    AnnotatedWidget(onTap: () {}, tooltip: 'Delete item');
