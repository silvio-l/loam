import 'dart:async';

import 'package:flutter/framework.dart';

class CleanPage extends StatefulWidget {
  const CleanPage({this.controller});

  final TextEditingController? controller;

  @override
  State createState() => _CleanState();
}

class _CleanState extends State<CleanPage> {
  final _direct = TextEditingController();
  final _inList = FocusNode();
  final _inLoop = FocusNode();
  final _viaHelper = ValueNotifier<int>(0);
  final _viaTransitive = ValueNotifier<int>(1);
  final _viaThis = FocusNode();
  Timer? _timer;
  StreamSubscription<int>? _sub;
  late TextEditingController _fromParam;
  late final FocusNode _neverCreated;
  late final TextEditingController _fromWidget = widget.controller!;
  final _maybeOwned = TextEditingController();

  // No dispose/close/cancel on the type: never flagged.
  final _portal = OverlayPortalController();
  final _plain = StringBuffer();
  final _list = <int>[];
  final _created = DateTime.now();
  final Timer _ticker = Timer.periodic(const Duration(seconds: 1), (_) {});

  _CleanState() {
    _fromParam = widget.controller ?? TextEditingController();
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 1), () {});
    _sub = Stream<int>.empty().listen((_) {});
  }

  void _releaseNotifiers() {
    _viaHelper.dispose();
    _releaseMore();
  }

  void _releaseMore() => _viaTransitive.dispose();

  @override
  void dispose() {
    _direct.dispose();
    for (final node in [_inList]) {
      node.dispose();
    }
    [_inLoop].forEach((n) => n.dispose());
    this._viaThis.dispose();
    _timer?.cancel();
    _sub?.cancel();
    _ticker.cancel();
    _releaseNotifiers();
    _maybeOwned.dispose();
    super.dispose();
  }
}

/// Values handed in from outside are not owned by the class.
class Borrowed {
  Borrowed(this._focus, {required this.controller});

  final FocusNode _focus;
  final TextEditingController controller;
  TextEditingController? _lazy;

  void attach(TextEditingController other) {
    _lazy = other;
  }

  void dispose() {}
}

/// No State and no dispose(): out of scope.
class NotAResourceOwner {
  final controller = TextEditingController();
}

/// `close()`/`cancel()` declared by Flutter or by the project itself are state
/// changes of a reusable controller, not a release.
class MenuController {
  void close() {}
}

class ClickGate {
  void cancel() {}
}

class _GateState extends State<CleanPage> {
  final _menu = MenuController();
  final _gate = ClickGate();
}
