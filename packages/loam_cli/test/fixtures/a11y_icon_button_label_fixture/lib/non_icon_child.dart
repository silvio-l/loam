// Negative fixture: GestureDetector / InkWell with a non-Icon child.
// The rule only fires when the child IS a pure Flutter Icon — here it is not,
// so no finding is expected.
import 'package:flutter/widgets.dart';

/// A non-Icon placeholder widget.
class MyLabel {
  /// Creates a [MyLabel].
  const MyLabel();
}

/// GestureDetector with a non-Icon child — no finding expected.
Object buildGestureWithNonIcon() =>
    GestureDetector(child: const MyLabel(), onTap: null);

/// InkWell with no child at all — no finding expected.
Object buildInkWellNoChild() => InkWell(onTap: null);
