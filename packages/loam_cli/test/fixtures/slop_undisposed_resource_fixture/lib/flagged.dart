import 'dart:async';

import 'package:flutter/framework.dart';

class FlaggedPage extends StatefulWidget {
  const FlaggedPage();

  @override
  State createState() => _FlaggedState();
}

class _FlaggedState extends State<FlaggedPage> {
  // Flagged: never released.
  final _name = TextEditingController();
  // Flagged: assigned in initState.
  late FocusNode _focus;
  // Flagged: static factory constructor, only cancelled outside dispose.
  Timer? _tick;
  // Flagged: cascade on a creation.
  final _level = ValueNotifier<int>(0)..value = 1;
  // Flagged: inherited release method (`dispose` of ChangeNotifier).
  final ChangeNotifier _notifier = ValueNotifier<int>(1);
  // Released properly, must stay clean.
  final _released = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  void stop() => _tick?.cancel();

  @override
  void dispose() {
    _released.dispose();
    super.dispose();
  }
}

/// Not a State, but declares its own dispose().
class Probe {
  // Flagged: a plain class with dispose() that forgets one field.
  final _level = ValueNotifier<int>(0);
  final _other = ValueNotifier<int>(0);
  final StreamController<int> _events = StreamController<int>();

  void dispose() {
    _other.dispose();
  }
}

/// A State without any dispose().
class _NoDisposeState extends State<FlaggedPage> {
  // Flagged: the class has no dispose() at all.
  final _text = TextEditingController();
}
