import 'dart:async';

import 'package:loam/src/timing/phase_timer.dart';
import 'package:loam/src/timing/run_watchdog.dart';
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;

/// A timer the test fires by hand, so no real time passes.
class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool cancelled = false;

  void fire() => _callback();

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  group('parseRunTimeout', () {
    test('reads seconds, units and the off values', () {
      expect(parseRunTimeout('600'), const Duration(seconds: 600));
      expect(parseRunTimeout('90s'), const Duration(seconds: 90));
      expect(parseRunTimeout('10m'), const Duration(minutes: 10));
      expect(parseRunTimeout(' 2H '), const Duration(hours: 2));
      expect(parseRunTimeout('0'), isNull);
      expect(parseRunTimeout('off'), isNull);
      expect(parseRunTimeout('none'), isNull);
    });

    test('rejects anything else', () {
      for (final bad in ['', 'abc', '-5', '1.5m', '10 days']) {
        expect(() => parseRunTimeout(bad), throwsFormatException, reason: bad);
      }
    });

    test('rejects values that would overflow into a negative duration', () {
      for (final huge in ['9999999999999h', '9223372036854775807', '366d']) {
        expect(
          () => parseRunTimeout(huge),
          throwsFormatException,
          reason: huge,
        );
      }
    });
  });

  group('resolveRunTimeout', () {
    test('flag beats environment beats the default', () {
      expect(resolveRunTimeout(), kDefaultRunTimeout);
      expect(resolveRunTimeout(env: '5m'), const Duration(minutes: 5));
      expect(
        resolveRunTimeout(flag: '30s', env: '5m'),
        const Duration(seconds: 30),
      );
      expect(resolveRunTimeout(flag: '0', env: '5m'), isNull);
      expect(resolveRunTimeout(env: ''), kDefaultRunTimeout);
    });

    test('an invalid environment value is an error, not silently ignored', () {
      expect(() => resolveRunTimeout(env: 'soon'), throwsFormatException);
    });
  });

  group('CLI wiring', () {
    test('an invalid --timeout is a usage error (exit 64)', () async {
      expect(await cli.run(['scan', '--timeout', 'soon']), 64);
    });

    test('the timeout exit code is 124, distinct from 1, 64 and 78', () {
      expect(kTimeoutExitCode, 124);
    });
  });

  group('WatchdogCore', () {
    late _ManualTimer timer;
    late List<String> messages;
    late WatchdogCore core;

    setUp(() {
      messages = [];
      core = WatchdogCore(
        limit: const Duration(minutes: 10),
        onExpire: messages.add,
        createTimer: (d, cb) => timer = _ManualTimer(d, cb),
      );
    });

    test('names the phase and the rule that was running', () {
      core.start();
      expect(timer.duration, const Duration(minutes: 10));
      core
        ..begin('rules', 0)
        ..begin('code-duplicates', 1);
      timer.fire();

      expect(messages, hasLength(1));
      expect(
        messages.single,
        contains("phase 'rules', rule 'code-duplicates'"),
      );
      expect(messages.single, contains('10 min'));
      expect(messages.single, contains('--timeout'));
      expect(messages.single, contains(kRunTimeoutEnv));
      expect(messages.single, contains('$kTimeoutExitCode'));
    });

    test('forgets a rule that already finished', () {
      core.start();
      core
        ..begin('rules', 0)
        ..begin('rule-a', 1)
        ..end('rule-a', 1);
      timer.fire();
      expect(messages.single, contains("phase 'rules'"));
      expect(messages.single, isNot(contains('rule-a')));
    });

    test('says so when no phase is active', () {
      core.start();
      timer.fire();
      expect(messages.single, contains('between phases'));
    });

    test('stop cancels the timer so a run in time never aborts', () {
      core.start();
      core.stop();
      expect(timer.cancelled, isTrue);
      expect(messages, isEmpty);
    });
  });

  test('PhaseTimer reports begin and end of phases and rules', () {
    final events = <String>[];
    var clock = Duration.zero;
    final timer = PhaseTimer(
      () => clock,
      onEvent: (label, depth, {required started}) =>
          events.add('${started ? '+' : '-'}$label@$depth'),
    );
    final stopRules = timer.begin('rules');
    final stopRule = timer.begin('rule-a', depth: 1);
    clock += const Duration(seconds: 1);
    stopRule();
    stopRule();
    stopRules();
    expect(events, ['+rules@0', '+rule-a@1', '-rule-a@1', '-rules@0']);
  });
}
