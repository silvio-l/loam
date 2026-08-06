/// Negative fixture for `a11y-interactive-semantics`.
///
/// Regression for the field-finding of 2026-08-06 (`WpButton`): a custom
/// widget that does NOT wrap itself in `Semantics(...)` at all — instead it
/// delegates its `label` argument transitively to an already-excluded
/// Flutter `ButtonStyleButton` subclass. The call site still carries
/// `label:`, so the rule must accept it as a sufficient accessible name
/// without ever inspecting `DelegatingButton`'s implementation.
library;

import 'package:flutter/widgets.dart';

/// Mirrors `WpButton`: delegates to a Flutter built-in, no internal
/// `Semantics(...)` call anywhere.
class DelegatingButton {
  /// Creates a [DelegatingButton].
  const DelegatingButton({required this.label, required this.onPressed});

  /// The accessible name, passed through to the wrapped Flutter button.
  final String label;

  /// Called when the button is pressed.
  final void Function() onPressed;

  /// Builds the widget by delegating to [ElevatedButton] — no `Semantics`
  /// call anywhere in this class.
  Object build() => ElevatedButton(onPressed: onPressed, child: null);
}

/// Negative case: call site passes `label:`. The rule must NOT flag this —
/// even though `DelegatingButton` itself never calls `Semantics(...)`.
Object buildDelegatingButton() =>
    DelegatingButton(label: 'Save changes', onPressed: () {});
