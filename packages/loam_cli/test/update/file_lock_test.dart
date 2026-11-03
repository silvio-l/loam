import 'dart:convert';
import 'dart:io';

import 'package:loam/src/update/file_lock.dart';
import 'package:loam/src/update/update_state.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('loam_lock_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  FileLock lock() => FileLock('${dir.path}/x.lock');

  group('FileLock', () {
    test('a second instance cannot take a held lock', () {
      final a = lock();
      final b = lock();
      expect(a.tryAcquire(), isTrue);
      expect(b.tryAcquire(), isFalse);
      a.release();
    });

    test('release frees the lock for the next instance', () {
      final a = lock()..tryAcquire();
      a.release();
      final b = lock();
      expect(b.tryAcquire(), isTrue);
      b.release();
    });

    test('release by an instance that never held the lock keeps it', () {
      final a = lock()..tryAcquire();
      lock().release();
      expect(lock().tryAcquire(), isFalse);
      a.release();
    });

    test('another process holds the lock, and frees it when it ends', () async {
      final script = File('${dir.path}/holder.dart')
        ..writeAsStringSync('''
import 'dart:io';
void main(List<String> args) {
  File(args[0]).openSync(mode: FileMode.append).lockSync(FileLock.exclusive);
  stdout.writeln('locked');
  stdin.listen((_) {}); // Held until stdin closes, then the process ends.
}
''');
      final holder = await Process.start(Platform.resolvedExecutable, [
        script.path,
        '${dir.path}/x.lock',
      ]);
      final lines = holder.stdout
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter());
      await lines.first; // Locked: event-driven, no timed wait.

      final mine = lock();
      expect(mine.tryAcquire(), isFalse);

      await holder.stdin.close();
      await holder.exitCode;
      expect(mine.tryAcquire(), isTrue, reason: 'the OS dropped the lock');
      mine.release();
    });
  });

  group('FileUpdateStateStore.update', () {
    FileUpdateStateStore store() =>
        FileUpdateStateStore(directory: dir.path, sleep: (_) {});

    test('writers of different fields do not overwrite each other', () {
      final a = store();
      final b = store();
      // Both processes "started" with the empty state; each only sets its own
      // field and the other one survives.
      b.update((s) => s.copyWith(latest: Version.parse('1.2.3')));
      a.update(
        (s) => s.copyWith(
          outcome: UpdateOutcome(
            kind: UpdateOutcomeKind.applied,
            from: Version.parse('1.0.0'),
            to: Version.parse('1.2.3'),
          ),
        ),
      );
      final state = store().read();
      expect(state.latest, Version.parse('1.2.3'));
      expect(state.outcome?.kind, UpdateOutcomeKind.applied);
    });

    test('the change sees the state another instance just wrote', () {
      final seen = <Version?>[];
      store().update((s) => s.copyWith(latest: Version.parse('2.0.0')));
      store().update((s) {
        seen.add(s.latest);
        return s;
      });
      expect(seen, [Version.parse('2.0.0')]);
    });

    test('a live lock held by another instance skips the write', () {
      final other = FileLock('${dir.path}/update_state.json.lock')
        ..tryAcquire();
      store().update((s) => s.copyWith(latest: Version.parse('3.0.0')));
      expect(store().read().latest, isNull);
      other.release();
      store().update((s) => s.copyWith(latest: Version.parse('3.0.0')));
      expect(store().read().latest, Version.parse('3.0.0'));
    });
  });
}
