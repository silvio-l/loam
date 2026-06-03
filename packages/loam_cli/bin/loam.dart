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
        ..addCommand(_GateCommand())
        ..addCommand(_BaselineCommand());

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
  final String description =
      'Full audit: run all active rules across the whole project '
      '(baseline-independent).';

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

/// Writes/updates the baseline — the bridge between the full audit and the
/// ratchet gate (see PRD D10 / ADR-0003). With no flag it shows the current
/// baseline; `--write` freezes the current findings as the accepted state.
class _BaselineCommand extends Command<int> {
  _BaselineCommand() {
    argParser.addFlag(
      'write',
      negatable: false,
      help:
          'Freeze the current findings as the new baseline '
          '(overwrites baseline.json).',
    );
  }

  @override
  final String name = 'baseline';
  @override
  final String description =
      'Show or freeze the baseline (--write) for the ratchet gate.';

  @override
  Future<int> run() async {
    final write = argResults?.flag('write') ?? false;
    stdout.writeln(
      write
          ? 'loam baseline --write: not yet implemented (will freeze baseline.json)'
          : 'loam baseline: not yet implemented (will show the current baseline)',
    );
    return 0;
  }
}
