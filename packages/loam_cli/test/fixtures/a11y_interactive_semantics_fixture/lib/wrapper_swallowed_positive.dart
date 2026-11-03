/// Positive fixture for `a11y-interactive-semantics`.
///
/// Project-defined wrappers that do NOT route a name to a semantic sink. Each
/// call site below must be reported, even when it passes `label:`.
library;

import 'package:flutter/widgets.dart';

/// Takes a `label` but never uses it for semantics.
class SwallowingButton {
  /// Creates a [SwallowingButton].
  const SwallowingButton({required this.label, required this.onPressed});

  /// Accepted and ignored.
  final String label;

  /// Called on press.
  final void Function() onPressed;

  /// Builds a button without any name.
  Object build() =>
      Semantics(button: true, child: GestureDetector(onTap: onPressed));
}

/// Forwards its label to a wrapper that swallows it.
class ForwardingButton {
  /// Creates a [ForwardingButton].
  const ForwardingButton({required this.caption, required this.onPressed});

  /// Forwarded to [SwallowingButton.label].
  final String caption;

  /// Called on press.
  final void Function() onPressed;

  /// Builds the swallowing inner wrapper.
  Object build() => SwallowingButton(label: caption, onPressed: onPressed);
}

/// Labelled wrapper, but the call site omits the name.
class NeedsTitle {
  /// Creates a [NeedsTitle].
  const NeedsTitle({this.title, required this.onTap});

  /// Reaches `Semantics(label:)`.
  final String? title;

  /// Called on tap.
  final void Function() onTap;

  /// Builds the tile.
  Object build() => Semantics(label: title, child: null);
}

/// Swallowed although `label:` is passed: one finding.
Object buildSwallowed() => SwallowingButton(label: 'Save', onPressed: () {});

/// Swallowed one level down: one finding.
Object buildForwardedToSwallower() =>
    ForwardingButton(caption: 'Save', onPressed: () {});

/// Name parameter omitted: one finding.
Object buildMissingTitle() => NeedsTitle(onTap: () {});

/// Second call of the same swallower: still no extra finding.
Object buildSwallowedAgain() =>
    SwallowingButton(label: 'Delete', onPressed: () {});

/// A `Text` beside an unnamed icon button names nothing.
class IconBesideText {
  /// Creates an [IconBesideText].
  const IconBesideText({required this.title, required this.onPressed});

  /// Visible, but not part of the tapped area.
  final String title;

  /// Called on press.
  final void Function() onPressed;

  /// Builds an icon button next to a caption.
  Object build() => Row(
    children: [
      IconButton(onPressed: onPressed, icon: const Icon(null)),
      const Text('Titel'),
    ],
  );
}

/// Swallowed because the text is not inside the tapped area: one finding.
Object buildIconBesideText() => IconBesideText(title: 'x', onPressed: () {});

/// Half of a cycle: builds [PongButton] and swallows its label.
class PingButton {
  /// Creates a [PingButton].
  const PingButton({this.label = '', required this.onPressed});

  /// Accepted and ignored.
  final String label;

  /// Called on press.
  final void Function() onPressed;

  /// Builds the other half of the cycle.
  Object build() => PongButton(onPressed: () {});
}

/// Other half of a cycle: builds [PingButton] and swallows its label.
class PongButton {
  /// Creates a [PongButton].
  const PongButton({this.label = '', required this.onPressed});

  /// Accepted and ignored.
  final String label;

  /// Called on press.
  final void Function() onPressed;

  /// Builds the other half of the cycle.
  Object build() => PingButton(onPressed: () {});
}

/// Mutually building swallowers: one finding for the pair.
Object buildCycle() => PingButton(label: 'Save', onPressed: () {});
