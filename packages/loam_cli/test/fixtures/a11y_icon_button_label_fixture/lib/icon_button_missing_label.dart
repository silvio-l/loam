// Positive fixture (AC1): IconButton without tooltip and without enclosing
// Semantics(label: …) → rule MUST emit one finding.
import 'package:flutter/widgets.dart';

/// An icon button with no tooltip and no Semantics wrapper.
/// The a11y-icon-button-label rule must report a finding here.
Object buildMissingTooltip() =>
    const IconButton(icon: Icon(42), onPressed: null);
