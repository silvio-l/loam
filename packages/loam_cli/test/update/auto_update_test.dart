import 'package:loam/src/update/auto_update.dart';
import 'package:loam/src/update/latest_version_fetcher.dart';
import 'package:loam/src/update/self_updater.dart';
import 'package:loam/src/update/update_policy.dart';
import 'package:loam/src/update/update_state.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

class _MemoryStore implements UpdateStateStore {
  _MemoryStore([this.state = UpdateState.empty]);

  UpdateState state;

  @override
  UpdateState read() => state;

  @override
  void update(UpdateState Function(UpdateState current) change) =>
      state = change(state);
}

/// A store whose write lock is held by another instance: `update` skips the
/// change, as [FileUpdateStateStore] does, and `read` still serves old data.
class _LockedStore extends _MemoryStore {
  _LockedStore(super.state);

  @override
  void update(UpdateState Function(UpdateState current) change) {}
}

class _FakeFetcher implements LatestVersionFetcher {
  _FakeFetcher(this.version);

  final Version? version;

  @override
  Future<Version?> fetchLatest(String packageName) async => version;
}

class _FakeInstaller implements SelfInstaller {
  _FakeInstaller([this.reason]);

  final String? reason;
  final installed = <Version>[];

  @override
  Future<String?> install(Version target) async {
    installed.add(target);
    return reason;
  }
}

final _now = DateTime.utc(2026, 11, 3, 12);
final _v15 = Version.parse('0.1.15');
final _v16 = Version.parse('0.1.16');

void main() {
  group('AutoUpdateCoordinator.afterRun', () {
    late _MemoryStore store;
    late List<UpdateMode> spawned;

    AutoUpdateCoordinator coordinator() => AutoUpdateCoordinator(
      current: _v15,
      currentRuleIds: const ['a'],
      upgradeCommand: 'brew upgrade loam',
      store: store,
      spawnWorker: (mode) async => spawned.add(mode),
      now: () => _now,
    );

    setUp(() {
      store = _MemoryStore();
      spawned = [];
    });

    test('write lock held by another run → no crash, no worker', () async {
      final locked = _LockedStore(UpdateState(latest: _v16));
      final coordinator = AutoUpdateCoordinator(
        current: _v15,
        currentRuleIds: const ['a'],
        upgradeCommand: 'brew upgrade loam',
        store: locked,
        spawnWorker: (mode) async => spawned.add(mode),
        now: () => _now,
      );
      await coordinator.afterRun(UpdateMode.notify);
      expect(spawned, isEmpty);
      expect(coordinator.takeAnnouncements(), isEmpty);
    });

    test('off → no worker, no notice, state untouched', () async {
      expect(await coordinator().afterRun(UpdateMode.off), isEmpty);
      expect(spawned, isEmpty);
      expect(store.state.checkedAt, isNull);
    });

    test('due check → claims the timestamp, then starts one worker', () async {
      await coordinator().afterRun(UpdateMode.auto);
      expect(spawned, [UpdateMode.auto]);
      expect(store.state.checkedAt, _now);

      // A second run right after finds the claim and starts nothing.
      await coordinator().afterRun(UpdateMode.auto);
      expect(spawned, [UpdateMode.auto]);
    });

    test(
      'notify + newer version known → notice with the channel command',
      () async {
        store.state = UpdateState(latest: _v16, checkedAt: _now);
        final lines = await coordinator().afterRun(UpdateMode.notify);
        expect(lines.single, contains('0.1.16'));
        expect(lines.single, contains('brew upgrade loam'));
        expect(spawned, isEmpty);
      },
    );

    test(
      'auto + newer version known → no notice (the worker installs)',
      () async {
        store.state = UpdateState(latest: _v16, checkedAt: _now);
        expect(await coordinator().afterRun(UpdateMode.auto), isEmpty);
      },
    );
  });

  group('AutoUpdateCoordinator.takeAnnouncements', () {
    AutoUpdateCoordinator coordinator(_MemoryStore store, Version current) =>
        AutoUpdateCoordinator(
          current: current,
          currentRuleIds: const ['a', 'c'],
          upgradeCommand: 'dart pub global activate loam',
          store: store,
          spawnWorker: (_) async {},
          now: () => _now,
        );

    test('applied update is reported once by the new version, with the '
        'ruleset change', () {
      final store = _MemoryStore(
        UpdateState(
          outcome: UpdateOutcome(
            kind: UpdateOutcomeKind.applied,
            from: _v15,
            to: _v16,
            previousRuleIds: const ['a', 'b'],
          ),
        ),
      );
      final lines = coordinator(store, _v16).takeAnnouncements();
      expect(lines.first, contains('0.1.15 to 0.1.16'));
      expect(lines.join('\n'), contains('new rules: c'));
      expect(lines.join('\n'), contains('removed rules: b'));
      expect(coordinator(store, _v16).takeAnnouncements(), isEmpty);
    });

    test('applied update is not claimed by an older running binary', () {
      final store = _MemoryStore(
        UpdateState(
          outcome: UpdateOutcome(
            kind: UpdateOutcomeKind.applied,
            from: _v15,
            to: _v16,
          ),
        ),
      );
      expect(coordinator(store, _v15).takeAnnouncements(), isEmpty);
      expect(store.state.outcome!.reported, isFalse);
    });

    test('failed update → reason and manual command, once', () {
      final store = _MemoryStore(
        UpdateState(
          outcome: UpdateOutcome(
            kind: UpdateOutcomeKind.failed,
            from: _v15,
            to: _v16,
            reason: 'checksum mismatch',
          ),
        ),
      );
      final lines = coordinator(store, _v15).takeAnnouncements();
      expect(lines.single, contains('checksum mismatch'));
      expect(lines.single, contains('dart pub global activate loam'));
      expect(coordinator(store, _v15).takeAnnouncements(), isEmpty);
    });
  });

  group('describeRulesetChange', () {
    test('same rules or unknown previous rules → nothing', () {
      expect(describeRulesetChange(['a'], ['a']), isEmpty);
      expect(describeRulesetChange([], ['a']), isEmpty);
    });
  });

  group('UpdateWorker', () {
    UpdateWorker worker(
      _MemoryStore store,
      Version? latest, {
      SelfInstaller? installer,
    }) => UpdateWorker(
      current: _v15,
      currentRuleIds: const ['a'],
      store: store,
      fetcher: _FakeFetcher(latest),
      installer: installer,
      now: () => _now,
    );

    test('check only → records latest and time, installs nothing', () async {
      final store = _MemoryStore();
      await worker(store, _v16).run();
      expect(store.state.latest, _v16);
      expect(store.state.checkedAt, _now);
      expect(store.state.outcome, isNull);
    });

    test(
      'offline (fetch fails) → keeps the old latest, records the time',
      () async {
        final store = _MemoryStore(UpdateState(latest: _v15));
        final installer = _FakeInstaller();
        await worker(store, null, installer: installer).run();
        expect(store.state.latest, _v15);
        expect(store.state.checkedAt, _now);
        expect(installer.installed, isEmpty);
      },
    );

    test(
      'newer version → installs it and records the applied outcome',
      () async {
        final store = _MemoryStore();
        final installer = _FakeInstaller();
        await worker(store, _v16, installer: installer).run();
        expect(installer.installed, [_v16]);
        expect(store.state.outcome!.kind, UpdateOutcomeKind.applied);
        expect(store.state.outcome!.previousRuleIds, ['a']);
      },
    );

    test('install failure → failed outcome with reason', () async {
      final store = _MemoryStore();
      await worker(store, _v16, installer: _FakeInstaller('no network')).run();
      expect(store.state.outcome!.kind, UpdateOutcomeKind.failed);
      expect(store.state.outcome!.reason, 'no network');
    });

    test('same or older version → no install', () async {
      final installer = _FakeInstaller();
      await worker(_MemoryStore(), _v15, installer: installer).run();
      expect(installer.installed, isEmpty);
    });
  });

  group('UpdateState persistence', () {
    test('round-trips through JSON', () {
      final state = UpdateState(
        latest: _v16,
        checkedAt: _now,
        outcome: UpdateOutcome(
          kind: UpdateOutcomeKind.failed,
          from: _v15,
          to: _v16,
          reason: 'x',
          previousRuleIds: const ['a'],
        ),
      );
      final decoded = UpdateState.decode(state.encode());
      expect(decoded.latest, _v16);
      expect(decoded.checkedAt, _now);
      expect(decoded.outcome!.kind, UpdateOutcomeKind.failed);
      expect(decoded.outcome!.previousRuleIds, ['a']);
    });

    test('corrupt file → empty state instead of a crash', () {
      expect(UpdateState.decode('{oops').latest, isNull);
    });
  });
}
