/// Overlap-exclusion fixture for `a11y-interactive-semantics`.
///
/// Uses Flutter built-in interactive widgets that are already handled by
/// dedicated sibling rules. The `a11y-interactive-semantics` rule must NOT
/// emit any findings here (zero double-counting).
///
/// Note: some widgets here ARE flagged by their respective sibling rules
/// (e.g. [IconButton] without tooltip triggers `a11y-icon-button-label`).
/// This fixture only asserts the absence of findings from the NEW rule.
library;

import 'package:flutter/widgets.dart';

void _noop() {}

/// [IconButton] without tooltip — covered by `a11y-icon-button-label`, NOT by
/// `a11y-interactive-semantics` (because IconButton is in package:flutter).
Object buildIconButtonNoTooltip() =>
    const IconButton(icon: Icon(null), onPressed: _noop);

/// [TextField] — covered by `a11y-form-field-label`, NOT by
/// `a11y-interactive-semantics` (because TextField is in package:flutter).
Object buildTextField() => const TextField();
