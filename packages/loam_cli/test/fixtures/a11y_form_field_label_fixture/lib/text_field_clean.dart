// Negative fixtures (AC2): clean cases — rule must NOT fire for any of these.
import 'package:flutter/widgets.dart';

/// TextField with an explicit labelText — accessible label provided.
/// No finding expected.
Object buildWithLabelText() =>
    const TextField(decoration: InputDecoration(labelText: 'Full name'));

/// TextField with hintText — accepted as a fallback label.
/// No finding expected.
Object buildWithHintText() =>
    const TextField(decoration: InputDecoration(hintText: 'Search…'));

/// TextField wrapped in Semantics(label: …) — accessible name from ancestor.
/// No finding expected.
Object buildInSemantics() =>
    Semantics(label: 'Email address', child: const TextField());
