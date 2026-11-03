// Edge cases: only real `//` comments count; `type=lint` has no reason.

/// ignore: not_a_directive_in_a_doc_comment
void docCommentIsNotADirective() {}

/// A string that merely contains the text.
const stringIsNotADirective = '// ignore: avoid_print';

/// Unjustified type selector.
void typeSelectorWithoutReason() {
  // ignore: type=lint
  print('x');
}

/// Justified type selector.
void typeSelectorWithReason() {
  // ignore: type=lint – generated debug output, reviewed
  print('x');
}
