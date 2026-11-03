// Negative fixture: the name comes from a Tooltip ancestor or the Icon itself.
import 'package:flutter/widgets.dart';

/// IconButton inside Tooltip(message:) - Tooltip announces the message.
Object buildInTooltip() => const Tooltip(
  message: 'Save',
  child: IconButton(icon: Icon(42), onPressed: null),
);

/// IconButton whose Icon carries a semanticLabel.
Object buildLabelledIcon() =>
    const IconButton(icon: Icon(42, semanticLabel: 'Add'), onPressed: null);

/// InkWell whose Icon child carries a semanticLabel.
Object buildInkWellLabelledIcon() =>
    InkWell(child: const Icon(42, semanticLabel: 'Close'), onTap: null);

/// GestureDetector with an Icon child inside Tooltip(message:).
Object buildGestureInTooltip() => Tooltip(
  message: 'Delete',
  child: GestureDetector(child: const Icon(42), onTap: null),
);
