// Positive fixtures (AC1): TextField/TextFormField without any label source
// → rule MUST emit a finding for each.
import 'package:flutter/widgets.dart';

/// A bare TextField with no decoration at all.
/// The a11y-form-field-label rule must report a finding here.
Object buildBareTextField() => const TextField();

/// A TextField with InputDecoration but no labelText and no hintText.
/// Still missing a label — the rule must report a finding here too.
Object buildDecorationNoLabel() =>
    const TextField(decoration: InputDecoration());
