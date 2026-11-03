// Negative fixture: an ancestor labels or deliberately hides the image.
import 'package:flutter/widgets.dart';

/// Image under Semantics(label:).
Object buildInSemanticsLabel() =>
    Semantics(label: 'Hero', child: Image.asset('assets/hero.png'));

/// Image under Semantics(excludeSemantics: true).
Object buildInSemanticsExclude() => Semantics(
  excludeSemantics: true,
  child: Image.asset('assets/decoration.png'),
);

/// Image under ExcludeSemantics.
Object buildInExcludeSemantics() =>
    ExcludeSemantics(child: Image.asset('assets/decoration.png'));

/// Dot shorthand with a semanticLabel.
Image buildShorthandLabelled() => .asset('assets/logo.png', semanticLabel: 'x');

/// Dot shorthand under ExcludeSemantics.
Object buildShorthandExcluded() => ExcludeSemantics(child: _shorthand());

Image _shorthand() =>
    .asset('assets/decoration.png', excludeFromSemantics: true);
