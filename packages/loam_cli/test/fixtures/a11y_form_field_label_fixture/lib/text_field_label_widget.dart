// Negative fixture: label: Text(…) names the field.
import 'package:flutter/widgets.dart';

/// InputDecoration(label: Text(…)) - Flutter renders it as the field label.
Object buildWithLabelWidget() =>
    const TextField(decoration: InputDecoration(label: Text('Name')));

/// Same for TextFormField.
Object buildFormFieldWithLabelWidget() =>
    const TextFormField(decoration: InputDecoration(label: Text('Email')));
