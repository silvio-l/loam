import 'package:loam/src/timing/phase_timer.dart';
import 'package:test/test.dart';

void main() {
  late Duration clock;
  late PhaseTimer timer;

  setUp(() {
    clock = const Duration(seconds: 100);
    timer = PhaseTimer(() => clock);
  });

  test('records durations from the injected clock in start order', () {
    final stopRules = timer.begin('rules');
    final stopA = timer.begin('rule-a', depth: 1);
    clock += const Duration(milliseconds: 300);
    stopA();
    final stopB = timer.begin('rule-b', depth: 1);
    clock += const Duration(milliseconds: 1200);
    stopB();
    stopRules();

    final e = timer.entries;
    expect(e.map((x) => x.label), ['rules', 'rule-a', 'rule-b']);
    expect(e.map((x) => x.duration.inMilliseconds), [1500, 300, 1200]);
    expect(timer.total, const Duration(milliseconds: 1500));
  });

  test('stopping twice keeps the first measurement', () {
    final stop = timer.begin('setup');
    clock += const Duration(milliseconds: 40);
    stop();
    clock += const Duration(seconds: 5);
    stop();
    expect(timer.entries.single.duration.inMilliseconds, 40);
  });

  test('measure records the duration even when the action throws', () {
    expect(
      () => timer.measure('report', () {
        clock += const Duration(milliseconds: 7);
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(timer.entries.single.duration.inMilliseconds, 7);
  });

  test('time is a plain call while no timer is active', () {
    PhaseTimer.active = null;
    expect(PhaseTimer.time('x', () => 42), 42);
  });

  test('time records into the active timer', () {
    PhaseTimer.active = timer;
    addTearDown(() => PhaseTimer.active = null);
    PhaseTimer.time('report', () => clock += const Duration(milliseconds: 9));
    expect(timer.entries.single.label, 'report');
    expect(timer.entries.single.duration.inMilliseconds, 9);
  });

  test('render lists nested entries, details and the total', () {
    final stop = timer.begin('resolve', detail: '12 files');
    clock += const Duration(milliseconds: 2500);
    stop();
    final stopRule = timer.begin('code-duplicates', depth: 1);
    clock += const Duration(milliseconds: 80);
    stopRule();

    final out = timer.render().split('\n');
    expect(out.first, 'loam timing');
    expect(out[1], contains('resolve'));
    expect(out[1], contains('2.50 s'));
    expect(out[1], contains('(12 files)'));
    expect(out[2], contains('  code-duplicates'));
    expect(out[2], contains('80 ms'));
    expect(out[3], contains('total'));
    expect(out[3], contains('2.58 s'));
  });
}
