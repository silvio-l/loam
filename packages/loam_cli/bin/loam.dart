import 'dart:io';

import 'package:args/command_runner.dart';

/// loam.dev CLI entrypoint (command: `loam`).
///
/// Walking-skeleton stub: the command surface is wired, individual
/// commands are filled in as tracer-bullet slices (see PRD §6).
Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'loam',
          'Codebase intelligence & anti-AI-slop for Dart/Flutter.',
        )
        ..addCommand(_ScanCommand())
        ..addCommand(_GateCommand());

  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}

class _ScanCommand extends Command<int> {
  @override
  final String name = 'scan';
  @override
  final String description = 'Run all active rules across the whole project.';

  @override
  Future<int> run() async {
    stdout.writeln(
      'loam scan: not yet implemented (tracer: unused-public-exports)',
    );
    return 0;
  }
}

class _GateCommand extends Command<int> {
  @override
  final String name = 'gate';
  @override
  final String description =
      'CI gate: baseline/ratchet (default) or --absolute.';

  @override
  Future<int> run() async {
    stdout.writeln('loam gate: not yet implemented');
    return 0;
  }
}
