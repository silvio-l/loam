import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../bin/loam.dart' as cli;

/// Result of an in-process CLI invocation.
class CliResult {
  CliResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs the real CLI entry point (`run` in `bin/loam.dart`) in this isolate and
/// captures what it writes to stdout/stderr.
///
/// Replaces `dart run bin/loam.dart` subprocesses: same code path, same exit
/// codes and bytes on the streams (no TTY, so no progress or ANSI), without the
/// JIT start-up cost per invocation.
Future<CliResult> runCli(List<String> args) async {
  final out = _CapturedStdout();
  final err = _CapturedStdout();
  final code = await IOOverrides.runZoned(
    () => cli.run(args),
    stdout: () => out,
    stderr: () => err,
  );
  return CliResult(code, out.text, err.text);
}

/// Minimal [Stdout] that records everything written to it.
class _CapturedStdout implements Stdout {
  final _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  Encoding encoding = utf8;

  @override
  bool get hasTerminal => false;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);

  @override
  void add(List<int> data) => _buffer.write(encoding.decode(data));

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} on captured stdout');
}
