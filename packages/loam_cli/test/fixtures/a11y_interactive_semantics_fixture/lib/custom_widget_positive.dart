/// Positive fixture for `a11y-interactive-semantics`.
///
/// Defines a generic, non-Flutter widget class with an [onTap] callback and
/// instantiates it WITHOUT a [Semantics] wrapper.  Expect exactly one finding
/// from the rule.
library;

/// A simple custom card widget with an [onTap] callback.
///
/// Not from `package:flutter` — the resolved library URI will be the fixture
/// package URI. This is the class the rule targets.
class CustomCard {
  /// Creates a [CustomCard].
  const CustomCard({required this.onTap, this.child});

  /// Called when the card is tapped.
  final void Function() onTap;

  /// Optional child (not a Flutter widget — typed as [Object?] to keep the
  /// fixture independent of any widget framework).
  final Object? child;
}

/// Positive case: [CustomCard] with [onTap] but WITHOUT a [Semantics] wrapper.
///
/// The `a11y-interactive-semantics` rule MUST emit one finding here.
Object buildUnaccessibleCard() => CustomCard(onTap: () {});
