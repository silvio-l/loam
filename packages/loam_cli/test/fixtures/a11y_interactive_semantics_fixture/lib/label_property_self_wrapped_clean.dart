/// Negative fixture for `a11y-interactive-semantics`.
///
/// Regression for the field-finding of 2026-06-23 (`LottiButton`): a custom
/// widget that encapsulates its own `Semantics(label: …)` internally and
/// exposes a `label` constructor argument at the call site. The rule must
/// recognise the call-site `label:` argument as a sufficient accessible name
/// and NOT require an additional `Semantics` wrapper around the call site —
/// which would produce doubled/nested semantics, an a11y anti-pattern.
library;

import 'package:flutter/widgets.dart';

/// Mirrors `LottiButton`: wraps its own semantics internally.
class SelfSemanticButton {
  /// Creates a [SelfSemanticButton].
  const SelfSemanticButton({required this.label, required this.onPressed});

  /// The accessible name, also used as the visible label.
  final String label;

  /// Called when the button is pressed.
  final void Function() onPressed;

  /// Builds the widget, wrapping itself in `Semantics(label: …)`.
  Object build() => Semantics(
    button: true,
    label: label,
    child: GestureDetector(onTap: onPressed),
  );
}

/// Negative case: call site passes `label:` directly. No `Semantics` wrapper
/// is needed here — the rule must NOT flag this.
Object buildSelfSemanticButton() =>
    SelfSemanticButton(label: 'Save changes', onPressed: () {});
