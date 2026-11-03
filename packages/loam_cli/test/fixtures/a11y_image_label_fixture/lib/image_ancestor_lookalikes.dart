// Positive fixture: ancestors that do NOT hide or label the image, so the rule
// MUST fire for each of these (4 findings, incl. dot shorthand).
import 'package:flutter/widgets.dart';

/// A project class named like Flutter's ExcludeSemantics - it must not count.
class LocalExcludeSemantics {
  /// Creates a [LocalExcludeSemantics].
  const LocalExcludeSemantics({this.child});

  /// The wrapped widget.
  final Object? child;
}

/// Lookalike ancestor.
Object buildInLookalike() =>
    LocalExcludeSemantics(child: Image.asset('assets/a.png'));

/// ExcludeSemantics(excluding: false) hides nothing.
Object buildNotExcluding() =>
    ExcludeSemantics(excluding: false, child: Image.asset('assets/b.png'));

/// Semantics without label and with excludeSemantics: false names nothing.
Object buildSemanticsWithoutLabel() =>
    Semantics(button: true, child: Image.asset('assets/c.png'));

/// Dot shorthand without any label.
Image buildShorthandUnlabelled() => .asset('assets/d.png');
