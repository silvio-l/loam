@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

// The capsule around the analyzer's internal API. After an analyzer upgrade
// that removes or changes that API, this import stops compiling — the error
// points at lib/src/loader/analyzer_cache.dart.
import 'package:loam/src/loader/analyzer_cache.dart';
import 'package:loam/src/loader/cache_eviction.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/progress/progress_sink.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_runner.dart';

/// Fixtures whose findings come from resolved (element-model) and cross-file
/// rules, the ones the summary store affects.
final _fixtures = [
  for (final name in [
    'a11y_interactive_semantics_fixture',
    'unused_exports_fixture',
  ])
    p.join(Directory.current.path, 'test', 'fixtures', name),
];

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('loam_az_cache_'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// Everything a report shows, so equality means "same result".
  Future<String> outcomeOf(String root, {String? store}) async {
    final outcome = await AnalysisRunner(
      analyzerCacheDirectory: store,
    ).analyze(root);
    return jsonEncode({
      'findings': [
        for (final f in outcome.findings)
          [f.ruleId, f.filePath, f.line, f.column, f.message, f.fingerprint],
      ],
      'suppressed': outcome.suppressedCount,
      'audit': outcome.suppressionAudit.toJson(),
      'files': outcome.stats.filesAnalyzed,
    });
  }

  List<File> storeFiles(String dir) =>
      Directory(dir).listSync(recursive: true).whereType<File>().toList();

  test('the internal store API still works: a run fills the store', () async {
    final store = p.join(temp.path, 'store');
    expect(AnalyzerCache.open(store), isNotNull);
    await outcomeOf(_fixtures.last, store: store);
    expect(
      storeFiles(store),
      isNotEmpty,
      reason:
          'the analyzer no longer writes through the injected byte store — '
          'check lib/src/loader/analyzer_cache.dart against the analyzer',
    );
  });

  test('a finished run leaves no write in flight: no temporary entries, the '
      'store can be removed at once', () async {
    // flush() of the analyzer's store returns at once on Windows
    // (dart-lang/sdk#64190); close() must still wait for the writes.
    final store = p.join(temp.path, 'store');
    await outcomeOf(_fixtures.last, store: store);
    expect([
      for (final f in storeFiles(store))
        if (p.basename(f.path).contains('-temp-')) f.path,
    ], isEmpty);
    Directory(store).deleteSync(recursive: true);
  });

  test('findings are identical without store, with a cold and a warm '
      'store', () async {
    for (final fixture in _fixtures) {
      final store = p.join(temp.path, p.basename(fixture));
      final plain = await outcomeOf(fixture);
      expect(jsonDecode(plain)['findings'], isNotEmpty);
      expect(await outcomeOf(fixture, store: store), plain, reason: 'cold');
      expect(await outcomeOf(fixture, store: store), plain, reason: 'warm');
    }
  });

  test('a corrupt store is ignored entry by entry', () async {
    final store = p.join(temp.path, 'store');
    final fixture = _fixtures.last;
    final plain = await outcomeOf(fixture, store: store);
    for (final file in storeFiles(store)) {
      file.writeAsBytesSync([1, 2, 3]);
    }
    expect(await outcomeOf(fixture, store: store), plain);
  });

  test('an unusable store location falls back to no store', () async {
    final blocker = File(p.join(temp.path, 'not-a-dir'))..writeAsStringSync('');
    final store = p.join(blocker.path, 'store');
    expect(AnalyzerCache.open(store), isNull);
    final fixture = _fixtures.last;
    expect(await outcomeOf(fixture, store: store), await outcomeOf(fixture));
  });

  test('a load that fails with the store reloads without it, discards the '
      'store and tells the user', () async {
    final store = p.join(temp.path, 'store');
    final fixture = _fixtures.last;
    final plain = await const ProjectLoader().load(fixture);
    final sink = _FailOnceSink();
    final result = await const ProjectLoader().load(
      fixture,
      cacheDirectory: store,
      progressSink: sink,
    );
    expect(
      [for (final f in result.resolved) f.path],
      [for (final f in plain.resolved) f.path],
    );
    expect(Directory(store).existsSync(), isFalse);
    expect(sink.notices, hasLength(1));
    expect(sink.notices.single, contains('StateError'));
  });

  group('evictOldest', () {
    /// A store entry last read [ageMinutes] ago and last written [writtenAgo]
    /// minutes ago (default: same time).
    File entry(String name, int bytes, int ageMinutes, {int? writtenAgo}) {
      final file = File(p.join(temp.path, 'ab', name))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(bytes, 0));
      file
        ..setLastModifiedSync(
          DateTime(2026).subtract(Duration(minutes: writtenAgo ?? ageMinutes)),
        )
        ..setLastAccessedSync(
          DateTime(2026).subtract(Duration(minutes: ageMinutes)),
        );
      return file;
    }

    test('keeps a store within the limit untouched', () {
      final files = [entry('a', 400, 3), entry('b', 400, 2)];
      expect(evictOldest(temp, maxBytes: 1000), 0);
      expect(files.every((f) => f.existsSync()), isTrue);
    });

    test('deletes least recently used first down to three quarters of the '
        'limit', () {
      // Written first but read last: the access time decides, not the write.
      final newest = entry('c', 400, 1, writtenAgo: 30);
      final oldest = entry('a', 400, 3);
      final middle = entry('b', 400, 2);
      expect(evictOldest(temp, maxBytes: 1000), 2);
      expect(oldest.existsSync(), isFalse);
      expect(middle.existsSync(), isFalse);
      expect(newest.existsSync(), isTrue);
    });

    test('never follows a symbolic link out of the store', () {
      final outside = Directory.systemTemp.createTempSync('loam_outside_');
      addTearDown(() => outside.deleteSync(recursive: true));
      final victim = File(p.join(outside.path, 'keep'))
        ..writeAsBytesSync(List.filled(4000, 0))
        ..setLastModifiedSync(DateTime(2000));
      Link(p.join(temp.path, 'ab', 'planted'))
        ..parent.createSync(recursive: true)
        ..createSync(outside.path);
      entry('a', 400, 1);
      evictOldest(temp, maxBytes: 100);
      expect(victim.existsSync(), isTrue);
      expect(
        AnalyzerCache.open(p.join(temp.path, 'ab', 'planted')),
        isNull,
        reason: 'a store root that is a link is not used at all',
      );
    }, skip: Platform.isWindows ? 'symbolic links need privileges' : false);
  });

  test('removeOrphanedTempFiles deletes only old temporary files at the '
      'top level', () {
    final now = DateTime(2026, 11, 3, 12);
    File file(String relative, Duration age) =>
        File(p.join(temp.path, relative))
          ..createSync(recursive: true)
          ..setLastModifiedSync(now.subtract(age));
    final orphan = file('ab12-temp-4711-cafe', const Duration(hours: 2));
    final inFlight = file('cd34-temp-4712-beef', const Duration(minutes: 1));
    final entry = file(p.join('ab', 'ab12'), const Duration(days: 3));
    expect(removeOrphanedTempFiles(temp, now: now), 1);
    expect(orphan.existsSync(), isFalse);
    expect(inFlight.existsSync(), isTrue, reason: 'a parallel run writes it');
    expect(entry.existsSync(), isTrue);
  });

  group('CLI wiring', () {
    late Directory project;
    late String store;

    setUp(() {
      project = Directory(p.join(temp.path, 'project'));
      File(p.join(project.path, 'pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          'name: store_fixture\nenvironment:\n  sdk: ^3.0.0\n',
        );
      File(p.join(project.path, 'lib', 'a.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('int answer() => 42;\n');
      store = p.join(project.path, '.dart_tool', 'loam', 'analyzer');
    });

    Future<void> scan(List<String> flags) async {
      final run = await runCli([
        '--no-update-check',
        ...flags,
        'scan',
        '--project-root',
        project.path,
      ]);
      expect(run.exitCode, isNot(anyOf(64, 70, 78)), reason: run.stderr);
    }

    test('keeps the store by default', () async {
      await scan([]);
      expect(storeFiles(store), isNotEmpty);
    });

    test('--no-cache leaves no store behind', () async {
      await scan(['--no-cache']);
      expect(Directory(store).existsSync(), isFalse);
    });

    test('cache: false in loam.yaml switches the store off', () async {
      File(
        p.join(project.path, 'loam.yaml'),
      ).writeAsStringSync('cache: false\n');
      await scan([]);
      expect(Directory(store).existsSync(), isFalse);
    });
  });
}

/// Fails the first load phase (the one with the store), records notices.
class _FailOnceSink implements ProgressSink {
  final notices = <String>[];
  var _failed = false;

  @override
  void startPhase(String label, {int? total}) {
    if (_failed) return;
    _failed = true;
    throw StateError('simulated failure while loading with the store');
  }

  @override
  void advance([int delta = 1]) {}

  @override
  void endPhase() {}

  @override
  void notice(String message) => notices.add(message);
}
