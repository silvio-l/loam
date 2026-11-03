/// Negative fixture for `a11y-interactive-semantics`.
///
/// Regression for the field-finding of 2026-08-06 (`WpButton`): a custom
/// widget that does NOT wrap itself in `Semantics(...)` at all — instead it
/// delegates its `label` argument to an already-excluded Flutter
/// `ButtonStyleButton` subclass, as that button's `Text` child. The wrapper
/// is read, finds the `Text` sink fed by `label`, and the call site passes
/// `label:`, so the rule accepts it. (A wrapper that dropped the label would
/// be reported: see `wrapper_swallowed_positive.dart`.)
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

  /// Builds the widget by delegating to [ElevatedButton] with the label as
  /// its text child — no `Semantics` call anywhere in this class.
  Object build() => ElevatedButton(onPressed: onPressed, child: Text(label));
}

/// Negative case: call site passes `label:`. The rule must NOT flag this —
/// even though `DelegatingButton` itself never calls `Semantics(...)`.
Object buildDelegatingButton() =>
    DelegatingButton(label: 'Save changes', onPressed: () {});
