import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:loam/src/command/loam_command.dart';

/// loam.dev CLI entrypoint (command: `loam`).
///
/// Walking-skeleton stub: the command surface is wired, individual
/// commands are filled in as tracer-bullet slices (see PRD §6).
Future<void> main(List<String> args) async {
  exit(await run(args));
}

/// Testable entry point: wires the runner and returns an exit code.
///
/// Callers (e.g. tests) drive this directly without forking a process.
/// [UsageException] is mapped to exit code **64** (EX_USAGE).
Future<int> run(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'loam',
          'Codebase intelligence & anti-AI-slop for Dart/Flutter.',
        )
        ..addCommand(ScanCommand())
        ..addCommand(_GateCommand())
        ..addCommand(_BaselineCommand());

  runner.argParser.addOption(
    'format',
    allowed: ['human', 'sarif', 'json', 'markdown', 'html'],
    defaultsTo: 'human',
    help: 'Output format.',
    allowedHelp: {
      'human': 'Human-readable text (default).',
      'sarif': 'SARIF 2.1 JSON (CI/tooling).',
      'json': 'Machine-readable JSON.',
      'markdown': 'Markdown (agent/LLM pipelines).',
      'html': 'Self-contained HTML report.',
    },
  );

  try {
    final code = await runner.run(args) ?? 0;
    return code;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  }
}

/// Full audit: runs all active rules across the whole project
/// (baseline-independent). Driven by [LoamCommand] base.
class ScanCommand extends LoamCommand {
  @override
  final String name = 'scan';
  @override
  final String description =
      'Full audit: run all active rules across the whole project '
      '(baseline-independent).';

  @override
  Future<int> run() => notImplemented('tracer: unused-public-exports');
}

class _GateCommand extends LoamCommand {
  @override
  final String name = 'gate';
  @override
  final String description =
      'CI gate: baseline/ratchet (default) or --absolute.';

  @override
  Future<int> run() => notImplemented('ratchet gate');
}

/// Writes/updates the baseline — the bridge between the full audit and the
/// ratchet gate (see PRD D10 / ADR-0003). With no flag it shows the current
/// baseline; `--write` freezes the current findings as the accepted state.
class _BaselineCommand extends LoamCommand {
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
    return notImplemented(
      write ? 'will freeze baseline.json' : 'will show the current baseline',
    );
  }
}
