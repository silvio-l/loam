import 'package:flutter/framework.dart';

Future<int> load() async => 1;

class Counter extends StatefulWidget {
  const Counter();

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int value = 0;

  Future<void> afterAwait() async {
    final v = await load();
    setState(() => value = v);
  }

  void inThen() {
    load().then((v) => setState(() => value = v));
  }

  void inWhenComplete() {
    load().whenComplete(() {
      setState(() => value = 0);
    });
  }

  Future<void> inTryAfterAwait() async {
    try {
      final v = await load();
      setState(() => value = v);
    } on Exception {
      value = -1;
    }
  }

  Future<void> inCatchAfterAwait() async {
    try {
      await load();
    } on Exception {
      setState(() => value = -1);
    }
  }

  Future<void> inFinallyAfterAwait() async {
    try {
      await load();
    } finally {
      setState(() => value = 0);
    }
  }

  Future<void> guardBeforeTheAwait() async {
    if (!mounted) return;
    await load();
    this.setState(() => value = 2);
  }

  Future<void> awaitInCondition() async {
    if (await load() > 0) {
      setState(() => value = 3);
    }
  }

  Future<void> awaitForLoop(Stream<int> values) async {
    await for (final v in values) {
      setState(() => value = v);
    }
  }

  void inAsyncClosure() {
    final handler = () async {
      await load();
      setState(() => value = 4);
    };
    handler();
  }

  Future<void> awaitInAnEarlyExitCondition() async {
    if (!await load().then((v) => v > 0)) return;
    setState(() => value = 5);
  }

  Future<void> awaitAfterTheGuard() async {
    await load();
    if (!mounted) return;
    await load();
    setState(() => value = 6);
  }
}
