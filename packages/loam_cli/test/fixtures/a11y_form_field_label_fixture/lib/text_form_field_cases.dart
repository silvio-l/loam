// TextFormField fixtures (AC3): both positive and negative cases.
import 'package:flutter/widgets.dart';

/// TextFormField without any decoration — missing label.
/// The a11y-form-field-label rule must report a finding here.
Object buildBareTextFormField() => const TextFormField();

/// TextFormField with an explicit labelText — accessible label provided.
/// No finding expected.
Object buildTextFormFieldWithLabel() =>
    const TextFormField(decoration: InputDecoration(labelText: 'Password'));
