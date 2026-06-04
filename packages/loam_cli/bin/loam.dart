import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/command/loam_command.dart';
import 'package:loam/src/gate/gate_engine.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/reporter_dispatch.dart';
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
/// Renders findings via the [Reporter] selected by `--format` (default: human).
/// Exit-code semantics: 1 when any findings are present, 0 when clean.
/// The reporter is a pure renderer — it has no influence on the exit code
/// (Invariant 4).
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

    // Resolve the format from the global --format option.
    final format = (globalResults?['format'] as String?) ?? 'human';

    // Resolve reporter — FormatNotImplementedError surfaces as a usage error.
    final Reporter reporter;
    try {
      reporter = reporterFor(format);
    } on FormatNotImplementedError catch (e) {
      stderr.writeln(e.toString());
      return 64; // EX_USAGE
    }

    final findings = await const AnalysisRunner().run(projectRoot);

    final payload = ReportPayload(
      findings: findings,
      projectRoot: projectRoot,
      rulesetVersion: AnalysisRunner.rulesetVersion,
      toolVersion: '0.0.2',
      isTty: stdout.hasTerminal,
    );

    stdout.write(reporter.render(payload));

    return findings.isNotEmpty ? 1 : 0;
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

/// CI gate: evaluates the current findings against the baseline.
///
/// **Default mode — Ratchet** (Invariant 3): only NEW findings fail the build.
/// Kept (frozen legacy) and fixed findings are always transparent.
///
/// **Absolute mode** (`--absolute`): all current findings are evaluated against
/// a fixed threshold (default 0). The baseline is not read at all — suitable
/// for greenfield projects or CI pipelines that require zero findings.
///
/// Note: `loam gate --absolute` with threshold 0 and `loam scan` share the
/// same exit-code semantics by design (PRD). They remain separate commands:
/// scan is the full-audit report; gate is the dedicated pass/fail decision.
class _GateCommand extends LoamCommand {
  _GateCommand() {
    argParser
      ..addFlag(
        'absolute',
        negatable: false,
        help:
            'Absolute mode: evaluate all current findings against a fixed '
            'threshold (default 0) — the baseline is ignored. '
            'Use for greenfield projects.',
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
  final String name = 'gate';
  @override
  final String description =
      'CI gate: baseline/ratchet (default) or --absolute threshold mode.';

  @override
  Future<int> run() async {
    final projectRoot =
        argResults?['project-root'] as String? ?? Directory.current.path;
    final absoluteMode = argResults?.flag('absolute') ?? false;

    if (absoluteMode) {
      return _runAbsolute(projectRoot);
    }
    return _runRatchet(projectRoot);
  }

  Future<int> _runAbsolute(String projectRoot) async {
    final findings = await const AnalysisRunner().run(projectRoot);
    final result = const GateEngine().evaluate(
      mode: GateMode.absolute,
      findings: findings,
    );

    final count = result.newCount;
    stdout.writeln(
      'loam gate --absolute: $count finding${count == 1 ? '' : 's'} '
      '— ${result.passed ? 'grün' : 'rot'}.',
    );

    return result.exitCode;
  }

  Future<int> _runRatchet(String projectRoot) async {
    final engine = BaselineEngine(projectRoot: projectRoot);

    // AC5: Missing baseline.json → clear error with hint.
    Baseline baseline;
    try {
      baseline = engine.read();
    } on BaselineException catch (e) {
      stderr.writeln('loam gate: ${e.message}');
      stderr.writeln(
        'Hint: run `loam baseline --write` first, '
        'or use `loam gate --absolute` for a threshold-based check.',
      );
      return 1;
    }

    // AC4: rulesetVersion mismatch → warning on stderr, diff continues normally.
    if (baseline.rulesetVersion != AnalysisRunner.rulesetVersion) {
      stderr.writeln(
        'loam gate: warning — baseline rulesetVersion '
        '(${baseline.rulesetVersion}) differs from current '
        '(${AnalysisRunner.rulesetVersion}). '
        'Consider refreshing with `loam baseline --update`.',
      );
    }

    final findings = await const AnalysisRunner().run(projectRoot);
    final diff = engine.diff(findings, baseline);
    final result = const GateEngine().evaluate(
      mode: GateMode.ratchet,
      diff: diff,
    );

    // AC3: Terse summary line to stdout (neu/eingefroren/gefixt).
    stdout.writeln(
      'loam gate: ${result.newCount} neu, '
      '${result.keptCount} eingefroren, '
      '${result.fixedCount} gefixt '
      '— ${result.passed ? 'grün' : 'rot'}.',
    );

    return result.exitCode;
  }
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
