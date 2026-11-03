// Positive fixture: lookalike classes and an unlabelled Icon do not name the
// button, so the rule MUST fire for each of these.
import 'package:flutter/widgets.dart';

/// A project class named like Flutter's Tooltip - it must not count.
class LocalTooltip {
  /// Creates a [LocalTooltip].
  const LocalTooltip({required this.message, this.child});

  /// Unused text.
  final String message;

  /// The wrapped widget.
  final Object? child;
}

/// IconButton inside a lookalike Tooltip is not named.
Object buildNoMessage() => const LocalTooltip(
  message: 'Save',
  child: IconButton(icon: Icon(42), onPressed: null),
);

/// IconButton with an Icon that has no semanticLabel stays unnamed.
Object buildPlainIcon() => const IconButton(icon: Icon(42), onPressed: null);
