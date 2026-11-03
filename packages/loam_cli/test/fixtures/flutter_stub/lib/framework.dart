/// Minimal stubs of Flutter framework classes for loam.dev test fixtures
/// (`State`, `BuildContext` and the resources a `State` typically owns).
library;

/// Stub of Flutter's `BuildContext`.
abstract class BuildContext {
  /// Whether the widget of this context is still in the tree.
  bool get mounted;
}

/// Stub of Flutter's `StatefulWidget`.
abstract class StatefulWidget {
  /// Creates the widget.
  const StatefulWidget();

  /// Creates its state.
  State createState();
}

/// Stub of Flutter's `State`.
abstract class State<T extends StatefulWidget> {
  /// The widget this state belongs to.
  late T widget;

  /// Called once when the state is inserted.
  void initState() {}

  /// Called when the state is removed for good.
  void dispose() {}

  /// The location of this state's widget in the tree.
  BuildContext get context => _element!;
  BuildContext? _element;

  /// Whether this state is still in the tree.
  bool get mounted => false;

  /// Schedules a rebuild after [fn] changed the state
  /// (`slop-setstate-after-async-gap` resolves calls to this method).
  void setState(void Function() fn) => fn();
}

/// Stub of Flutter's `ChangeNotifier`.
class ChangeNotifier {
  /// Releases listeners.
  void dispose() {}
}

/// Stub of Flutter's `ValueNotifier`.
class ValueNotifier<T> extends ChangeNotifier {
  /// Creates a notifier holding [value].
  ValueNotifier(this.value);

  /// The current value.
  T value;
}

/// Stub of Flutter's `TextEditingController`.
class TextEditingController extends ValueNotifier<String> {
  /// Creates a controller.
  TextEditingController() : super('');
}

/// Stub of Flutter's `FocusNode`.
class FocusNode extends ChangeNotifier {}

/// Stub of Flutter's `OverlayPortalController`: it has no `dispose`.
class OverlayPortalController {
  /// Creates a controller.
  OverlayPortalController();
}
