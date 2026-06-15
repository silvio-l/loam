/// Negative fixture for `a11y-interactive-semantics`.
///
/// The [CustomCard] widget is wrapped in [Semantics] with a non-null `label`
/// argument. Expect ZERO findings.
library;

import 'package:flutter/widgets.dart';

/// A simple custom card widget with an [onTap] callback.
///
/// Defined here independently of [custom_widget_positive.dart] to keep fixture
/// files self-contained.
class CustomCard {
  /// Creates a [CustomCard].
  const CustomCard({required this.onTap, this.child});

  /// Called when the card is tapped.
  final void Function() onTap;

  /// Optional child.
  final Object? child;
}

/// Negative case: [CustomCard] wrapped in [Semantics] with a `label`.
///
/// The `a11y-interactive-semantics` rule must NOT emit a finding here.
Object buildAccessibleCard() => Semantics(
  label: 'Card action',
  child: CustomCard(onTap: () {}),
);
