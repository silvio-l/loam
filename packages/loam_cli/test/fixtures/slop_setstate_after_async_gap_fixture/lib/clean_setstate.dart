import 'package:flutter/framework.dart';

Future<int> load() async => 1;

class Panel extends StatefulWidget {
  const Panel();

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  int value = 0;
  bool busy = false;

  Future<void> exitGuard() async {
    final v = await load();
    if (!mounted) return;
    setState(() => value = v);
  }

  Future<void> exitGuardInBlock() async {
    await load();
    if (!mounted) {
      return;
    }
    setState(() => value = 1);
  }

  Future<void> contextGuard() async {
    await load();
    if (!context.mounted) return;
    setState(() => value = 2);
  }

  Future<void> throwGuard() async {
    await load();
    if (!mounted) throw StateError('gone');
    setState(() => value = 3);
  }

  Future<void> scopeGuard() async {
    await load();
    if (mounted) {
      setState(() => value = 4);
    }
  }

  Future<void> scopeGuardWithAnd(bool flag) async {
    await load();
    if (mounted && flag) setState(() => value = 5);
  }

  Future<void> conditionalGuard() async {
    await load();
    mounted ? setState(() => value = 6) : null;
  }

  Future<void> beforeTheFirstAwait() async {
    setState(() => busy = true);
    try {
      final v = await load();
      if (!mounted) return;
      setState(() => value = v);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void guardedThen() {
    load().then((v) {
      if (!mounted) return;
      setState(() => value = v);
    });
  }

  Future<void> wrapper() async {
    await load();
    safeSetState(() => value = 7);
  }

  void safeSetState(void Function() fn) {
    if (mounted) setState(fn);
  }

  Future<void> guardInsideEarlierBranch(bool flag) async {
    if (flag) {
      await load();
      if (!mounted) return;
    }
    setState(() => value = 8);
  }

  Future<void> laterClosure() async {
    await load();
    final cb = () => setState(() => value = 9);
    if (mounted) cb();
  }

  Future<void> awaitInsideAClosureOnly() async {
    final later = () async => load();
    setState(() => value = 10);
    await later();
  }

  Future<void> awaitOnlyInAnEarlyExit(bool flag) async {
    if (flag) {
      await load();
      return;
    }
    setState(() => value = 11);
  }
}

/// Not a Flutter `State`: a method of the same name.
class Store {
  int value = 0;

  void setState(void Function() fn) => fn();

  Future<void> refresh() async {
    await load();
    setState(() => value = 1);
  }
}
