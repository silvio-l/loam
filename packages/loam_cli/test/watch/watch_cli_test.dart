@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:loam/src/watch/watch_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_runner.dart';
import '../support/shared_store.dart';

/// A [StringSink] that lets a test wait until a number of writes happened.
class _Sink implements StringSink {
  final StringBuffer text = StringBuffer();
  int writes = 0;
  final List<(int, Completer<void>)> _waiters = [];

  Future<void> untilWrites(int n) {
    if (writes >= n) return Future.value();
    final completer = Completer<void>();
    _waiters.add((n, completer));
    return completer.future;
  }

  void _bump() {
    writes++;
    for (final (n, c) in _waiters) {
      if (writes >= n && !c.isCompleted) c.complete();
    }
  }

  @override
  void write(Object? object) {
    text.write(object);
    _bump();
  }

  @override
  void writeln([Object? object = '']) {
    text.writeln(object);
    _bump();
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));
}

void main() {
  useSharedAnalyzerStore();

  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('loam_watch_');
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: watch_project
publish_to: none
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
    Directory(p.join(project.path, 'lib')).createSync();
  });

  tearDown(() => project.deleteSync(recursive: true));

  void write(String name, String source) =>
      File(p.join(project.path, 'lib', name)).writeAsStringSync(source);

  test('rejects output formats other than human with exit 64', () async {
    final result = await runCli([
      '--format',
      'json',
      'watch',
      '--project-root',
      project.path,
    ]);
    expect(result.exitCode, 64);
  });

  test('rejects a debounce outside 0-60000 ms with exit 64', () async {
    for (final value in ['-1', '60001', 'soon']) {
      final result = await runCli([
        'watch',
        '--debounce',
        value,
        '--project-root',
        project.path,
      ]);
      expect(result.exitCode, 64, reason: value);
    }
  });

  test('a change reports findings that depend on other files and the ones '
      'that went away', () async {
    write('a.dart', 'class A {}\n');
    write('b.dart', 'class B {}\n');
    final root = p.normalize(project.path);

    Future<List<Finding>> fullRun() async =>
        (await AnalysisRunner().analyze(root)).findings;

    final events = StreamController<String>();
    final stop = StreamController<void>();
    final out = _Sink();
    final err = _Sink();
    final finished = runWatch(
      root: root,
      changes: events.stream,
      analyze: fullRun,
      renderFull: (findings) => 'initial ${findings.length}\n',
      out: out,
      err: err,
      stopRequests: stop.stream,
      debounce: Duration.zero,
    );

    await out.untilWrites(1);
    expect(out.text.toString(), startsWith('initial '));

    // a <-> b becomes an import cycle: a finding that exists only because
    // of the relation between the two files.
    write('a.dart', "import 'b.dart';\nclass A { B? b; }\n");
    write('b.dart', "import 'a.dart';\nclass B { A? a; }\n");
    events.add(p.join(root, 'lib', 'a.dart'));
    events.add(p.join(root, 'lib', 'b.dart'));
    await out.untilWrites(2);

    final delta = out.text.toString();
    expect(delta, contains('lib/a.dart, lib/b.dart changed'));
    expect(delta, contains('(+3 new, -2 resolved)'));
    expect(delta, contains('+ [circular-dependencies]'));

    stop.add(null);
    expect(await finished, 0);
    expect(events.hasListener, isFalse);
    unawaited(events.close());
    unawaited(stop.close());
  });
}
