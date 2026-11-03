import 'dart:async';
import 'dart:io';

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/watch/watch_runner.dart';
import 'package:loam/src/watch/watch_session.dart';
import 'package:test/test.dart';

/// Simulated time: timers fire only when [advance] moves the clock past them.
class _FakeClock {
  Duration now = Duration.zero;
  final List<_FakeTimer> timers = [];

  Timer create(Duration delay, void Function() action) {
    final timer = _FakeTimer(now + delay, action);
    timers.add(timer);
    return timer;
  }

  int get pendingTimers => timers.where((t) => t.isActive).length;

  Future<void> advance(Duration by) async {
    final target = now + by;
    while (true) {
      final due = timers.where((t) => t.isActive && t.at <= target).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      now = due.first.at;
      due.first.fire();
      await pumpEventQueue();
    }
    now = target;
    await pumpEventQueue();
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.at, this._action);

  final Duration at;
  final void Function() _action;
  bool _active = true;

  void fire() {
    _active = false;
    _action();
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

Finding _finding(String id, {String file = 'lib/a.dart'}) => Finding(
  ruleId: 'r',
  severity: Severity.warning,
  filePath: file,
  line: 1,
  message: 'm $id',
  fingerprint: id,
);

void main() {
  const root = '/proj';
  const debounce = Duration(milliseconds: 300);

  late _FakeClock clock;
  late StreamController<String> events;
  late List<WatchUpdate> updates;
  late List<List<Finding>> results;
  late Completer<void>? gate;
  var analyzeCalls = 0;
  Object? failNext;

  WatchSession? session;
  Future<void>? running;

  Future<void> start() async {
    final created = session = WatchSession(
      root: root,
      changes: events.stream,
      createTimer: clock.create,
      debounce: debounce,
      onUpdate: updates.add,
      analyze: () async {
        analyzeCalls++;
        final pending = gate;
        if (pending != null) await pending.future;
        final error = failNext;
        if (error != null) {
          failNext = null;
          throw error;
        }
        return results.removeAt(0);
      },
    );
    running = created.run();
    await pumpEventQueue();
  }

  Future<void> emit(String path) async {
    events.add(path);
    await pumpEventQueue();
  }

  setUp(() {
    clock = _FakeClock();
    events = StreamController<String>();
    updates = [];
    results = [];
    gate = null;
    analyzeCalls = 0;
    failNext = null;
  });

  tearDown(() async {
    await session?.stop();
    await running;
    session = null;
    running = null;
    unawaited(events.close());
  });

  test(
    'the first run starts at once and reports every finding as new',
    () async {
      results = [
        [_finding('a'), _finding('b')],
      ];
      await start();

      expect(updates, hasLength(1));
      expect(updates.single.isInitial, isTrue);
      expect(updates.single.added.map((f) => f.fingerprint), ['a', 'b']);
      expect(updates.single.changedPaths, isEmpty);
      expect(clock.pendingTimers, 0);
    },
  );

  test('a burst of events becomes one run after the quiet period', () async {
    results = [[], []];
    await start();

    await emit('/proj/lib/a.dart');
    await clock.advance(const Duration(milliseconds: 200));
    await emit('/proj/lib/b.dart');
    await clock.advance(const Duration(milliseconds: 200));
    expect(analyzeCalls, 1, reason: 'the quiet period restarts per event');

    await clock.advance(const Duration(milliseconds: 100));
    expect(analyzeCalls, 2);
    expect(updates.last.changedPaths, ['lib/a.dart', 'lib/b.dart']);
  });

  test('events that cannot change the result start no run', () async {
    results = [[]];
    await start();

    for (final path in [
      '/proj/baseline.json',
      '/proj/.dart_tool/loam/analyzer/x.dart',
      '/proj/build/gen.dart',
      '/proj/README.md',
      '/elsewhere/lib/a.dart',
    ]) {
      await emit(path);
    }
    await clock.advance(const Duration(seconds: 5));

    expect(analyzeCalls, 1);
  });

  test('changes during a run lead to exactly one follow-up run', () async {
    results = [[], []];
    await start();

    final held = gate = Completer<void>();
    await emit('/proj/lib/a.dart');
    await clock.advance(debounce);
    expect(analyzeCalls, 2);

    await emit('/proj/lib/b.dart');
    await emit('/proj/lib/c.dart');
    await clock.advance(const Duration(seconds: 5));
    expect(analyzeCalls, 2, reason: 'no overlapping runs');

    gate = null;
    results.add([]);
    held.complete();
    await pumpEventQueue();
    await clock.advance(debounce);

    expect(analyzeCalls, 3);
    expect(updates.last.changedPaths, ['lib/b.dart', 'lib/c.dart']);
  });

  test('added and resolved findings are told apart by fingerprint', () async {
    results = [
      [_finding('keep'), _finding('gone')],
      [_finding('keep'), _finding('new')],
    ];
    await start();

    await emit('/proj/lib/a.dart');
    await clock.advance(debounce);

    final update = updates.last;
    expect(update.added.map((f) => f.fingerprint), ['new']);
    expect(update.resolved.map((f) => f.fingerprint), ['gone']);
    expect(update.findings.map((f) => f.fingerprint), ['keep', 'new']);
  });

  test('a failing run is reported and the next change retries', () async {
    results = [
      [_finding('a')],
      [_finding('a'), _finding('b')],
    ];
    await start();

    failNext = StateError('broken loam.yaml');
    await emit('/proj/loam.yaml');
    await clock.advance(debounce);
    expect(updates.last.error, isA<StateError>());
    expect(updates.last.findings.map((f) => f.fingerprint), ['a']);

    await emit('/proj/loam.yaml');
    await clock.advance(debounce);
    expect(updates.last.error, isNull);
    expect(updates.last.added.map((f) => f.fingerprint), ['b']);
  });

  test(
    'a failing first run propagates and releases the event stream',
    () async {
      failNext = StateError('no sdk');
      final failing = WatchSession(
        root: root,
        changes: events.stream,
        createTimer: clock.create,
        onUpdate: updates.add,
        analyze: () async => throw failNext!,
      );
      await expectLater(failing.run(), throwsA(isA<StateError>()));
      expect(events.hasListener, isFalse);
    },
  );

  test(
    'an output that throws stops the session without unhandled errors',
    () async {
      results = [
        [],
        [_finding('a')],
      ];
      var delivered = 0;
      final created = session = WatchSession(
        root: root,
        changes: events.stream,
        createTimer: clock.create,
        debounce: debounce,
        analyze: () async => results.removeAt(0),
        onUpdate: (_) {
          if (++delivered == 2) throw const FileSystemException('broken pipe');
        },
      );
      running = created.run();
      await pumpEventQueue();

      await emit('/proj/lib/a.dart');
      await clock.advance(debounce);
      await running;

      expect(created.outputError, isA<FileSystemException>());
      expect(delivered, 2, reason: 'no second delivery attempt');
      expect(events.hasListener, isFalse);
      expect(clock.pendingTimers, 0);
    },
  );

  test('stop cancels the pending run and the subscription', () async {
    results = [[]];
    await start();

    await emit('/proj/lib/a.dart');
    expect(clock.pendingTimers, 1);

    await session!.stop();
    await running;

    expect(clock.pendingTimers, 0);
    expect(events.hasListener, isFalse);
    await clock.advance(const Duration(seconds: 5));
    expect(analyzeCalls, 1);
  });

  test('stop waits for the running analysis before run completes', () async {
    results = [[], []];
    await start();

    final held = gate = Completer<void>();
    await emit('/proj/lib/a.dart');
    await clock.advance(debounce);

    var stopped = false;
    final stopping = session!.stop().then((_) => stopped = true);
    await pumpEventQueue();
    expect(stopped, isFalse);

    gate = null;
    held.complete();
    await stopping;
    await running;
    expect(updates, hasLength(2), reason: 'the in-flight result is delivered');
  });

  group('isRelevantChange', () {
    test(
      'accepts Dart sources and the config files that steer the analysis',
      () {
        for (final path in [
          '/proj/lib/a.dart',
          '/proj/bin/x.dart',
          'lib/relative.dart',
          '/proj/pubspec.yaml',
          '/proj/analysis_options.yaml',
          '/proj/loam.yaml',
        ]) {
          expect(isRelevantChange(root, path), isTrue, reason: path);
        }
      },
    );

    test('rejects loam output, tool state, build output and outsiders', () {
      for (final path in [
        '/proj/baseline.json',
        '/proj/loam-report.html',
        '/proj/.dart_tool/package_config.json',
        '/proj/.git/hooks/x.dart',
        '/proj/build/out.dart',
        '/proj/lib/notes.md',
        '/other/lib/a.dart',
      ]) {
        expect(isRelevantChange(root, path), isFalse, reason: path);
      }
    });
  });

  group('renderWatchDelta', () {
    test('names the trigger, the totals and each added/resolved finding', () {
      final text = renderWatchDelta(
        WatchUpdate(
          run: 2,
          findings: [_finding('b')],
          added: [_finding('b')],
          resolved: [_finding('a')],
          changedPaths: const ['lib/a.dart'],
        ),
      );
      expect(text, contains('lib/a.dart changed'));
      expect(text, contains('1 finding (+1 new, -1 resolved)'));
      expect(text, contains('+ [r] lib/a.dart:1 m b'));
      expect(text, contains('- [r] lib/a.dart:1 m a'));
    });
  });
}
