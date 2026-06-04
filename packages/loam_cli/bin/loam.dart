import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/command/loam_command.dart';
import 'package:loam/src/runner/analysis_runner.dart';

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
        ..addCommand(_HealthCommand())
        ..addCommand(_GateCommand())
        ..addCommand(_BaselineCommand())
        ..addCommand(_SlopCommand())
        ..addCommand(_InitCommand())
        ..addCommand(_FixCommand());

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
///
/// Output is provisional and minimal (Sprint 5 transition marker).
/// Polished reporters (human/sarif/…) replace this in Sprint 6 —
/// only the renderer changes, the pipeline stays identical (Invariant 4).
class ScanCommand extends LoamCommand {
  ScanCommand() {
    argParser.addOption(
      'project-root',
      abbr: 'p',
      help:
          'Root directory of the Dart project to analyse. '
          'Defaults to the current working directory.',
      defaultsTo: null,
    );
  }

  @override
  final String name = 'scan';
  @override
  final String description =
      'Full audit: run all active rules across the whole project '
      '(baseline-independent).';

  @override
  Future<int> run() async {
    final projectRoot =
        argResults?['project-root'] as String? ?? Directory.current.path;

    final runner = const AnalysisRunner();
    final findings = await runner.run(projectRoot);

    // Provisional minimal output — Sprint 6 replaces this renderer only.
    for (final f in findings) {
      stdout.writeln('[${f.ruleId}] ${f.filePath}:${f.line} ${f.message}');
    }

    final count = findings.length;
    if (count == 0) {
      stdout.writeln('loam scan: 0 findings — clean.');
    } else {
      stdout.writeln(
        'loam scan: $count finding${count == 1 ? '' : 's'} '
        '(provisional output — full reporters in Sprint 6)',
      );
    }

    return count > 0 ? 1 : 0;
  }
}

/// Project health score: aggregates active rules into a single health metric.
class _HealthCommand extends LoamCommand {
  @override
  final String name = 'health';
  @override
  final String description =
      'Show project health score: aggregates complexity, drift, and slop metrics.';

  @override
  Future<int> run() =>
      notImplemented('aggregate complexity/drift/slop into health score');
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

/// AI-slop audit: runs slop-focused rules across the whole project.
class _SlopCommand extends LoamCommand {
  @override
  final String name = 'slop';
  @override
  final String description =
      'AI-slop audit: run slop-focused rules across the whole project.';

  @override
  Future<int> run() => notImplemented(
    'slop-focused rules: empty catch, filler comments, dead guards',
  );
}

/// Initialises loam.dev configuration in the current project.
class _InitCommand extends LoamCommand {
  @override
  final String name = 'init';
  @override
  final String description =
      'Initialise loam.dev configuration (loam.yaml) in the current project.';

  @override
  Future<int> run() =>
      notImplemented('scaffold loam.yaml with default ruleset');
}

/// Applies mechanical fixes for findings that have a safe auto-fix.
class _FixCommand extends LoamCommand {
  @override
  final String name = 'fix';
  @override
  final String description =
      'Apply mechanical fixes for findings that have a safe auto-fix.';

  @override
  Future<int> run() =>
      notImplemented('apply mechanical fixes for auto-fixable findings');
}

/// Writes/updates the baseline — the bridge between the full audit and the
/// ratchet gate (see PRD D10 / ADR-0003). With no flag it shows the current
/// baseline; `--write` freezes the current findings as the accepted state;
/// `--update` refreshes an existing baseline.
class _BaselineCommand extends LoamCommand {
  _BaselineCommand() {
    argParser
      ..addFlag(
        'write',
        negatable: false,
        help:
            'Freeze the current findings as the new baseline. '
            'Warns if baseline.json already exists (use --update to refresh).',
      )
      ..addFlag(
        'update',
        negatable: false,
        help:
            'Refresh an existing baseline with the current findings. '
            'Warns if no baseline.json exists yet (use --write to create one).',
      )
      ..addOption(
        'project-root',
        abbr: 'p',
        help:
            'Root directory of the Dart project to analyse. '
            'Defaults to the current working directory.',
        defaultsTo: null,
      );
  }

  @override
  final String name = 'baseline';
  @override
  final String description =
      'Show or freeze the baseline (--write / --update) for the ratchet gate.';

  @override
  Future<int> run() async {
    final write = argResults?.flag('write') ?? false;
    final update = argResults?.flag('update') ?? false;
    final projectRoot =
        argResults?['project-root'] as String? ?? Directory.current.path;

    final engine = BaselineEngine(projectRoot: projectRoot);

    if (write) {
      return _runWrite(engine, projectRoot);
    } else if (update) {
      return _runUpdate(engine, projectRoot);
    } else {
      return _runShow(engine);
    }
  }

  Future<int> _runWrite(BaselineEngine engine, String projectRoot) async {
    if (engine.exists) {
      stderr.writeln(
        'Warning: baseline.json already exists in $projectRoot. '
        'Use `loam baseline --update` to refresh it '
        '(--write would overwrite your curated baseline).',
      );
    }
    final findings = await const AnalysisRunner().run(projectRoot);
    engine.write(findings, AnalysisRunner.rulesetVersion);
    final count = findings.length;
    stdout.writeln(
      'loam baseline: wrote $count finding${count == 1 ? '' : 's'} '
      'to baseline.json (${AnalysisRunner.rulesetVersion}).',
    );
    return 0;
  }

  Future<int> _runUpdate(BaselineEngine engine, String projectRoot) async {
    if (!engine.exists) {
      stderr.writeln(
        'Warning: no baseline.json found in $projectRoot. '
        'Use `loam baseline --write` to create one.',
      );
    }
    final findings = await const AnalysisRunner().run(projectRoot);
    engine.write(findings, AnalysisRunner.rulesetVersion);
    final count = findings.length;
    stdout.writeln(
      'loam baseline: updated to $count finding${count == 1 ? '' : 's'} '
      'in baseline.json (${AnalysisRunner.rulesetVersion}).',
    );
    return 0;
  }

  int _runShow(BaselineEngine engine) {
    try {
      final baseline = engine.read();
      final count = baseline.findings.length;
      stdout.writeln(
        'loam baseline: $count finding${count == 1 ? '' : 's'} '
        '(${baseline.rulesetVersion}, schemaVersion=${baseline.schemaVersion})',
      );
      for (final f in baseline.findings) {
        stdout.writeln(
          '  [${f.ruleId}] ${f.filePath}:${f.line} ${f.message} '
          '(${f.fingerprint})',
        );
      }
    } on BaselineException catch (e) {
      stderr.writeln('loam baseline: ${e.message}');
      return 1;
    }
    return 0;
  }
}
