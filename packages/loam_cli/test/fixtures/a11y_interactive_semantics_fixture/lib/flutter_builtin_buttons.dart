/// Regression fixture: Flutter built-in interactive widgets must NOT be flagged
/// by `a11y-interactive-semantics`.
///
/// `ButtonStyleButton` subclasses (`ElevatedButton`, `TextButton`, …) derive
/// their accessible name from their `child:` text widget via Flutter's
/// automatic semantics merging — no additional `Semantics(label:)` ancestor is
/// required. `Semantics` itself is the accessibility provider; flagging it when
/// it carries both `label:` and `onTap:` would be circular.
///
/// All instantiations here are from `package:flutter` — the rule excludes the
/// entire `package:flutter` namespace. Expect **zero findings** from
/// `a11y-interactive-semantics` in this file.
library;

import 'package:flutter/widgets.dart';

void _noop() {}

/// [ElevatedButton] with onPressed and a text child — no Semantics ancestor.
///
/// Flutter merges the child text's semantics into the button automatically.
/// The `a11y-interactive-semantics` rule MUST NOT flag this.
Object buildElevatedButtonNoSemantics() =>
    const ElevatedButton(onPressed: _noop, child: null);

/// [TextButton] with onPressed — no Semantics ancestor.
///
/// Same merging behaviour as [ElevatedButton].
/// The `a11y-interactive-semantics` rule MUST NOT flag this.
Object buildTextButtonNoSemantics() =>
    const TextButton(onPressed: _noop, child: null);

/// [Semantics] widget with both `label:` and `onTap:` — self-labelling pattern.
///
/// `Semantics(label: '...', onTap: ...)` IS the accessibility node; it provides
/// its own accessible name via [Semantics.label]. The rule MUST NOT flag this
/// because [Semantics] is from `package:flutter` and is itself the accessibility
/// provider.
Object buildSelfLabelledSemantics() =>
    const Semantics(label: 'dismiss', onTap: _noop, child: null);
