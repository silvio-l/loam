@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/progress/progress_sink.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Recording [ProgressSink] that captures all events for assertion.
class _RecordingSink implements ProgressSink {
  final List<_Event> events = [];

  @override
  void startPhase(String label, {int? total}) {
    events.add(_StartPhase(label, total));
  }

  @override
  void advance([int delta = 1]) {
    events.add(_Advance(delta));
  }

  @override
  void endPhase() {
    events.add(_EndPhase());
  }

  // Convenience: count advance events at the given position in events list.
  int advanceCount() =>
      events.whereType<_Advance>().fold(0, (sum, a) => sum + a.delta);
}

// Event model -----------------------------------------------------------------

abstract class _Event {}

class _StartPhase implements _Event {
  _StartPhase(this.label, this.total);
  final String label;
  final int? total;
}

class _Advance implements _Event {
  _Advance(this.delta);
  final int delta;
}

class _EndPhase implements _Event {}

// Tests -----------------------------------------------------------------------

void main() {
  // Use cross_file_fixture: 5 Dart files (lib/app.dart, lib/greeter.dart,
  // bin/main.dart, test/greeter_test.dart, tool/generate.dart).
  final fixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'cross_file_fixture'),
  );

  group('ProjectLoader.load ProgressSink event sequence', () {
    late _RecordingSink sink;
    late ProjectLoadResult loadResult;

    setUpAll(() async {
      sink = _RecordingSink();
      loadResult = await const ProjectLoader().load(
        fixturePath,
        progressSink: sink,
      );
    });

    test('first event is startPhase with label "Lade Projekt"', () {
      expect(sink.events, isNotEmpty);
      final first = sink.events.first;
      expect(first, isA<_StartPhase>());
      expect((first as _StartPhase).label, equals('Lade Projekt'));
    });

    test('startPhase carries a non-zero total (number of Dart files)', () {
      final start = sink.events.first as _StartPhase;
      expect(start.total, isNotNull);
      expect(start.total, greaterThan(0));
    });

    test('total matches the number of resolved files', () {
      final start = sink.events.first as _StartPhase;
      // total = all dart files collected (resolved + errors + parts)
      final total = start.total!;
      // The fixture has 5 Dart files, all should be resolvable.
      expect(total, equals(5));
    });

    test('advance is called once per dart file', () {
      // advance calls between startPhase and endPhase
      final advanceCalls = sink.events
          .whereType<_Advance>()
          .where((_) => true)
          .length;
      final start = sink.events.first as _StartPhase;
      expect(advanceCalls, equals(start.total));
    });

    test('last event is endPhase', () {
      expect(sink.events.last, isA<_EndPhase>());
    });

    test('order is startPhase → advance(×N) → endPhase', () {
      expect(sink.events.first, isA<_StartPhase>());
      expect(sink.events.last, isA<_EndPhase>());
      // all middle events are advance
      final middle = sink.events.sublist(1, sink.events.length - 1);
      expect(middle.every((e) => e is _Advance), isTrue);
    });

    test('load result is still valid (sink does not corrupt it)', () {
      expect(loadResult.resolved, isNotEmpty);
    });
  });

  group('AnalysisRunner.analyze ProgressSink event sequence', () {
    late _RecordingSink sink;
    late AnalysisOutcome outcome;

    setUpAll(() async {
      sink = _RecordingSink();
      outcome = await AnalysisRunner(
        config: const LoamConfig.defaults(),
        progressSink: sink,
      ).analyze(fixturePath);
    });

    test('contains at least two startPhase events (load + analyse)', () {
      final starts = sink.events.whereType<_StartPhase>().toList();
      expect(starts.length, equals(2));
    });

    test('first phase is "Lade Projekt"', () {
      final starts = sink.events.whereType<_StartPhase>().toList();
      expect(starts[0].label, equals('Lade Projekt'));
    });

    test('second phase is "Analysiere"', () {
      final starts = sink.events.whereType<_StartPhase>().toList();
      expect(starts[1].label, equals('Analysiere'));
    });

    test('analyse phase total equals active rule count', () {
      final starts = sink.events.whereType<_StartPhase>().toList();
      final analyseTotal = starts[1].total;
      expect(analyseTotal, isNotNull);
      expect(
        analyseTotal,
        equals(
          AnalysisRunner.activeRuleIdsForConfig(
            const LoamConfig.defaults(),
          ).length,
        ),
      );
    });

    test('endPhase count equals startPhase count', () {
      final starts = sink.events.whereType<_StartPhase>().length;
      final ends = sink.events.whereType<_EndPhase>().length;
      expect(ends, equals(starts));
    });

    test('outcome is valid (sink does not corrupt analysis result)', () {
      expect(outcome.findings, isNotNull);
    });
  });

  group('NoopProgressSink', () {
    test('all methods are callable without throwing', () {
      const sink = NoopProgressSink();
      expect(() {
        sink.startPhase('Test', total: 10);
        sink.advance();
        sink.advance(3);
        sink.endPhase();
      }, returnsNormally);
    });
  });
}
