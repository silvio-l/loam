// Negative fixture (AC3): clean cases — rule must NOT fire for any of these.
import 'package:flutter/widgets.dart';

/// IconButton with tooltip — accessible name provided via tooltip.
/// No finding expected.
Object buildWithTooltip() =>
    const IconButton(icon: Icon(42), tooltip: 'Close', onPressed: null);

/// IconButton wrapped in Semantics(label: …) — accessible name provided via Semantics.
/// No finding expected.
Object buildIconButtonInSemantics() => Semantics(
  label: 'Close button',
  child: const IconButton(icon: Icon(42), onPressed: null),
);

/// GestureDetector with pure Icon child, but wrapped in Semantics(label: …).
/// No finding expected.
Object buildGestureInSemantics() => Semantics(
  label: 'Delete item',
  child: GestureDetector(child: const Icon(42), onTap: null),
);

/// InkWell with pure Icon child, but wrapped in Semantics(label: …).
/// No finding expected.
Object buildInkWellInSemantics() => Semantics(
  label: 'Add item',
  child: InkWell(child: const Icon(42), onTap: null),
);
