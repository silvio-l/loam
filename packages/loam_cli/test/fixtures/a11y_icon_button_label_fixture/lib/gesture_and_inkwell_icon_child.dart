// Positive fixture (AC2): GestureDetector / InkWell whose child is a pure Icon
// without an enclosing Semantics(label: …) → rule MUST emit one finding each.
import 'package:flutter/widgets.dart';

/// GestureDetector with a pure Icon child and no Semantics wrapper.
/// The a11y-icon-button-label rule must report a finding here.
Object buildGestureWithIcon() =>
    GestureDetector(child: const Icon(42), onTap: null);

/// InkWell with a pure Icon child and no Semantics wrapper.
/// The a11y-icon-button-label rule must report a finding here too.
Object buildInkWellWithIcon() => InkWell(child: const Icon(42), onTap: null);
