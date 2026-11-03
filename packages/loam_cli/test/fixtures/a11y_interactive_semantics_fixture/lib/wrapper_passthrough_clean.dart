/// Negative fixture for `a11y-interactive-semantics`.
///
/// Project-defined wrappers that route a name to a semantic sink. The
/// parameter names deliberately differ from `label`/`semanticLabel`/`tooltip`,
/// so only reading the wrapper's source can tell they are labelled.
library;

import 'package:flutter/widgets.dart';

/// Passes `title` to `Semantics(label:)`.
class TitledTile {
  /// Creates a [TitledTile].
  const TitledTile({required this.title, required this.onTap});

  /// Reaches `Semantics(label:)`.
  final String title;

  /// Called on tap.
  final void Function() onTap;

  /// Builds the labelled tile.
  Object build() => Semantics(
    label: title,
    child: GestureDetector(onTap: onTap),
  );
}

/// Labels itself; call sites need no name.
class CloseButton {
  /// Creates a [CloseButton].
  const CloseButton({required this.onPressed});

  /// Called on press.
  final void Function() onPressed;

  /// Builds a button with a fixed tooltip.
  Object build() => Tooltip(
    message: 'Close',
    child: GestureDetector(onTap: onPressed),
  );
}

/// First of two levels: forwards `caption` to [TitledTile.title].
class OuterTile {
  /// Creates an [OuterTile].
  const OuterTile({required this.caption, required this.onTap});

  /// Forwarded to the inner wrapper.
  final String caption;

  /// Called on tap.
  final void Function() onTap;

  /// Builds the inner wrapper.
  Object build() => TitledTile(title: caption, onTap: onTap);
}

/// Stateful shape: the label is read as `widget.text` in the State.
class StatefulTile {
  /// Creates a [StatefulTile].
  const StatefulTile({required this.text, required this.onTap});

  /// Read by the State.
  final String text;

  /// Called on tap.
  final void Function() onTap;

  /// Returns the State.
  Object createState() => _StatefulTileState();
}

class _StatefulTileState {
  late StatefulTile widget;

  Object build() => Semantics(label: widget.text, child: null);
}

/// Factory constructor: the wrapper cannot be read reliably, so the call
/// site's `label:` decides (fallback), not a "swallowed" verdict.
class FactoryTile {
  /// Creates a [FactoryTile] through a factory.
  factory FactoryTile({
    required String label,
    required void Function() onTap,
  }) => FactoryTile._(label, onTap);

  FactoryTile._(this.title, this.onTap);

  /// Reaches `Semantics(label:)`.
  final String title;

  /// Called on tap.
  final void Function() onTap;

  /// Builds the labelled tile.
  Object build() => Semantics(
    label: title,
    child: GestureDetector(onTap: onTap),
  );
}

/// Name passed directly: no Semantics wrapper needed.
Object buildTitled() => TitledTile(title: 'Open settings', onTap: () {});

/// The wrapper labels itself.
Object buildClose() => CloseButton(onPressed: () {});

/// Two levels deep: `caption` -> `title` -> `Semantics(label:)`.
Object buildTwoLevels() => OuterTile(caption: 'Open profile', onTap: () {});

/// Stateful wrapper.
Object buildStateful() => StatefulTile(text: 'Open help', onTap: () {});

/// Factory wrapper, named at the call site.
Object buildFactory() => FactoryTile(label: 'Open search', onTap: () {});

/// The `Text` lies inside the tapped area: it is the accessible name.
class TextInsideTap {
  /// Creates a [TextInsideTap].
  const TextInsideTap({required this.title, required this.onTap});

  /// Visible name inside the tapped area.
  final String title;

  /// Called on tap.
  final void Function() onTap;

  /// Builds the tappable row.
  Object build() => InkWell(
    onTap: onTap,
    child: Row(children: [const Icon(null), Text(title)]),
  );
}

/// A field handed to a widget inside the tapped area may carry the name: the
/// wrapper is not judged.
class ChildHolder {
  /// Creates a [ChildHolder].
  const ChildHolder({required this.child, required this.onTap, this.tooltip});

  /// Accepted by the call-site fallback only.
  final String? tooltip;

  /// Supplied by the caller.
  final Object child;

  /// Called on tap.
  final void Function() onTap;

  /// Builds the tappable area around the caller's widget.
  Object build() => InkWell(onTap: onTap, child: child);
}

/// Name inside the tapped area, found through the wrapper.
Object buildTextInsideTap() => TextInsideTap(title: 'Open', onTap: () {});

/// Name handed in as `child`; the wrapper is inconclusive, so the call site's
/// own `tooltip:` decides and nothing is reported at the definition.
Object buildChildHolder() =>
    ChildHolder(onTap: () {}, tooltip: 'Open', child: const Text('Open'));
