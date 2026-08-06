/// Positive fixture for `a11y-interactive-semantics`.
///
/// Edge case for the call-site accessible-name-property check: an EMPTY
/// string literal (`label: ''`) must NOT be accepted as an accessible name.
/// The rule stays conservative — only a non-empty value counts.
library;

/// A custom widget with a `label` property.
class LabelledCard {
  /// Creates a [LabelledCard].
  const LabelledCard({required this.label, required this.onTap});

  /// The accessible name.
  final String label;

  /// Called when the card is tapped.
  final void Function() onTap;
}

/// Positive case: `label: ''` is empty — the rule MUST still flag this.
Object buildEmptyLabelCard() => LabelledCard(label: '', onTap: () {});
