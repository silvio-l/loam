import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/command/loam_command.dart';
import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/config/config_scaffold.dart';
import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/gate/gate_engine.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/reporter_dispatch.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:loam/src/update/update_checker.dart';
import 'package:loam/src/update/update_notice.dart';
import 'package:loam/src/version.dart';
import 'package:path/path.dart' as p;

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

  runner.argParser
    ..addOption(
      'format',
      allowed: ['human', 'sarif', 'json', 'markdown', 'html'],
      defaultsTo: 'human',
      help: 'Output format.',
      allowedHelp: {
        'human': 'Human-readable text (default).',
        'sarif': 'SARIF 2.1 JSON (CI/tooling).',
        'json': 'Machine-readable JSON (agent/tooling integration).',
        'markdown': 'Markdown report (PR/docs embedding, agent/LLM pipelines).',
        'html':
            'Self-contained HTML report (stdout; redirect to loam-report.html).',
      },
    )
    ..addFlag(
      'no-update-check',
      negatable: false,
      help:
          'Skip the update-availability check for this run. '
          'See also: LOAM_NO_UPDATE_CHECK env var and '
          'update_check: false in loam.yaml.',
    );

  // Parse args once and reuse the result for both command dispatch and the
  // global --no-update-check peek — no double-parse. A parse error surfaces as
  // a UsageException → exit 64, exactly as CommandRunner.run would map it.
  final ArgResults topLevelResults;
  try {
    topLevelResults = runner.parse(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  }
  final noUpdateCheckFlag = topLevelResults.flag('no-update-check');

  int code;
  try {
    code = await runner.runCommand(topLevelResults) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  } on ConfigLoadException catch (e) {
    // A malformed/invalid loam.yaml surfaces here (thrown from _loadConfig in
    // scan/gate/baseline). Emit a clean one-line message — no raw stacktrace
    // (AC3: stacktrace-free) — and a non-zero exit code (78 = EX_CONFIG).
    stderr.writeln(e.toString());
    return 78;
  }

  // Update notice: shown after command output (last line), out-of-band on
  // stderr. Wrapped in try/catch so any error never affects the exit code.
  // (ADR-0004, CONTEXT.md Invariant 4/5).
  //
  // Precedence chain: --no-update-check (CLI) > LOAM_NO_UPDATE_CHECK (env,
  // handled inside UpdateChecker) > update_check: false (loam.yaml) >
  // default (on).
  //
  // Config is loaded from cwd as a best-effort; load failure is silently
  // swallowed so a broken loam.yaml never blocks the update notice.
  try {
    var configUpdateCheck = true;
    try {
      final config = await _loadConfig(Directory.current.path);
      configUpdateCheck = config.updateCheck;
    } catch (_) {
      // Config load failure → use default (on). The command itself already
      // surfaced the error via the ConfigLoadException path above.
    }

    final notice = await UpdateChecker(currentVersion: loamVersion).check(
      noUpdateCheckFlag: noUpdateCheckFlag,
      configUpdateCheck: configUpdateCheck,
    );
    if (notice != null) {
      stderr.writeln(formatUpdateNotice(notice));
    }
  } catch (_) {
    // Silently swallow any unexpected error — notice is optional.
  }

  return code;
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

    // Load project config (loam.yaml) — missing file returns defaults.
    final config = await _loadConfig(projectRoot);

    final findings = await AnalysisRunner(config: config).run(projectRoot);

    final payload = ReportPayload(
      findings: findings,
      projectRoot: projectRoot,
      rulesetVersion: AnalysisRunner.rulesetVersionForConfig(config),
      toolVersion: loamVersion,
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
      'Show project health score: aggregates complexity, drift, and slop metrics. '
      '(coming soon)';

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
///
/// Findings are rendered via the [Reporter] selected by `--format`.
/// The Gate-summary line and exit code are determined exclusively by
/// [GateEngine] — the reporter is a pure renderer (Invariant 4).
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

    // Resolve reporter — FormatNotImplementedError surfaces as a usage error.
    // Mirrors the pattern in ScanCommand (DRY — same catch path, same exit 64).
    final Reporter reporter;
    try {
      reporter = reporterFor(format);
    } on FormatNotImplementedError catch (e) {
      stderr.writeln(e.toString());
      return 64; // EX_USAGE
    }

    // Load project config (loam.yaml) — missing file returns defaults.
    final config = await _loadConfig(projectRoot);

    if (absoluteMode) {
      return _runAbsolute(projectRoot, reporter, config);
    }
    return _runRatchet(projectRoot, reporter, config);
  }

  Future<int> _runAbsolute(
    String projectRoot,
    Reporter reporter,
    LoamConfig config,
  ) async {
    final findings = await AnalysisRunner(config: config).run(projectRoot);
    final result = const GateEngine().evaluate(
      mode: GateMode.absolute,
      findings: findings,
    );

    // Render findings via reporter (pure display — does not influence exit code).
    if (findings.isNotEmpty) {
      final payload = ReportPayload(
        findings: findings,
        projectRoot: projectRoot,
        rulesetVersion: AnalysisRunner.rulesetVersionForConfig(config),
        toolVersion: loamVersion,
        isTty: stdout.hasTerminal,
      );
      stdout.write(reporter.render(payload));
    }

    // Gate-summary line comes exclusively from GateEngine (Invariant 4).
    final count = result.newCount;
    stdout.writeln(
      'loam gate --absolute: $count finding${count == 1 ? '' : 's'} '
      '— ${result.passed ? 'grün' : 'rot'}.',
    );

    return result.exitCode;
  }

  Future<int> _runRatchet(
    String projectRoot,
    Reporter reporter,
    LoamConfig config,
  ) async {
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
    final currentVersion = AnalysisRunner.rulesetVersionForConfig(config);
    if (baseline.rulesetVersion != currentVersion) {
      stderr.writeln(
        'loam gate: warning — baseline rulesetVersion '
        '(${baseline.rulesetVersion}) differs from current '
        '($currentVersion). '
        'Consider refreshing with `loam baseline --update`.',
      );
    }

    final findings = await AnalysisRunner(config: config).run(projectRoot);
    final diff = engine.diff(findings, baseline);
    final result = const GateEngine().evaluate(
      mode: GateMode.ratchet,
      diff: diff,
    );

    // Render current findings (all of them: new + kept) via reporter.
    // The reporter shows what is there now — gate-decision stays in GateEngine.
    // Only render when there are findings to show (avoids empty output noise).
    if (findings.isNotEmpty) {
      final payload = ReportPayload(
        findings: findings,
        projectRoot: projectRoot,
        rulesetVersion: AnalysisRunner.rulesetVersionForConfig(config),
        toolVersion: loamVersion,
        isTty: stdout.hasTerminal,
      );
      stdout.write(reporter.render(payload));
    }

    // AC3: Terse summary line to stdout (neu/eingefroren/gefixt).
    // This line comes exclusively from GateEngine — reporter has no influence
    // on the gate decision or exit code (Invariant 4).
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
      'AI-slop audit: run slop-focused rules across the whole project. '
      '(coming soon)';

  @override
  Future<int> run() => notImplemented(
    'slop-focused rules: empty catch, filler comments, dead guards',
  );
}

/// Initialises loam.dev configuration in the current project.
///
/// Writes a commented `loam.yaml` scaffold to the current project root.
/// If `loam.yaml` already exists, the command refuses to overwrite it and
/// exits with a non-zero code (no silent data loss).
class _InitCommand extends LoamCommand {
  _InitCommand() {
    argParser.addOption(
      'project-root',
      abbr: 'p',
      help:
          'Root directory of the Dart project. '
          'Defaults to the current working directory.',
      defaultsTo: null,
    );
  }

  @override
  final String name = 'init';
  @override
  final String description =
      'Scaffold a loam.yaml configuration file in the current project.';

  @override
  Future<int> run() async {
    final projectRoot =
        argResults?['project-root'] as String? ?? Directory.current.path;
    final target = File(p.join(projectRoot, ConfigLoader.fileName));

    if (target.existsSync()) {
      stderr.writeln(
        'loam init: ${ConfigLoader.fileName} already exists in $projectRoot — '
        'not overwriting. '
        'Edit it manually or delete it first.',
      );
      return 1;
    }

    final content = ConfigScaffold.generate();
    target.writeAsStringSync(content);
    stdout.writeln('loam init: wrote ${ConfigLoader.fileName} to $projectRoot');
    return 0;
  }
}

/// Applies mechanical fixes for findings that have a safe auto-fix.
class _FixCommand extends LoamCommand {
  @override
  final String name = 'fix';
  @override
  final String description =
      'Apply mechanical fixes for findings that have a safe auto-fix. '
      '(coming soon)';

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

    // Load project config (loam.yaml) — missing file returns defaults.
    final config = await _loadConfig(projectRoot);

    if (write) {
      return _runWrite(engine, projectRoot, config);
    } else if (update) {
      return _runUpdate(engine, projectRoot, config);
    } else {
      // Resolve reporter for the show path — FormatNotImplementedError → exit 64.
      // --write/--update always produce a plain confirmation line (no findings
      // to render), so reporter resolution only applies to the show path.
      final Reporter reporter;
      try {
        reporter = reporterFor(format);
      } on FormatNotImplementedError catch (e) {
        stderr.writeln(e.toString());
        return 64; // EX_USAGE
      }
      return _runShow(engine, projectRoot, reporter);
    }
  }

  Future<int> _runWrite(
    BaselineEngine engine,
    String projectRoot,
    LoamConfig config,
  ) async {
    if (engine.exists) {
      stderr.writeln(
        'Warning: baseline.json already exists in $projectRoot. '
        'Use `loam baseline --update` to refresh it '
        '(--write would overwrite your curated baseline).',
      );
    }
    final findings = await AnalysisRunner(config: config).run(projectRoot);
    final version = AnalysisRunner.rulesetVersionForConfig(config);
    engine.write(findings, version);
    final count = findings.length;
    stdout.writeln(
      'loam baseline: wrote $count finding${count == 1 ? '' : 's'} '
      'to baseline.json ($version).',
    );
    return 0;
  }

  Future<int> _runUpdate(
    BaselineEngine engine,
    String projectRoot,
    LoamConfig config,
  ) async {
    if (!engine.exists) {
      stderr.writeln(
        'Warning: no baseline.json found in $projectRoot. '
        'Use `loam baseline --write` to create one.',
      );
    }
    final findings = await AnalysisRunner(config: config).run(projectRoot);
    final version = AnalysisRunner.rulesetVersionForConfig(config);
    engine.write(findings, version);
    final count = findings.length;
    stdout.writeln(
      'loam baseline: updated to $count finding${count == 1 ? '' : 's'} '
      'in baseline.json ($version).',
    );
    return 0;
  }

  int _runShow(BaselineEngine engine, String projectRoot, Reporter reporter) {
    try {
      final baseline = engine.read();

      // BaselineFinding → Finding mapping decision (documented per issue AC):
      //
      // BaselineFinding deliberately does NOT carry severity or column — it is
      // a minimal, position-robust diff key (fingerprint) plus human-readable
      // context (ruleId, filePath, line, message). The baseline schema never
      // stored severity so we cannot recover it from disk without re-running
      // the analysis.
      //
      // Decision: map with Severity.warning as the default.
      // Rationale: "warning" is the neutral, non-alarming severity that avoids
      // over-stating (error) or under-stating (info) severity for frozen baseline
      // findings whose real severity is unknown. This is only cosmetic — the
      // baseline show path has no gate/exit-code semantics anyway.
      // column is set to null (BaselineFinding has no column field).
      final mappedFindings = baseline.findings
          .map(
            (bf) => Finding(
              ruleId: bf.ruleId,
              severity: Severity.warning, // documented default (see above)
              filePath: bf.filePath,
              line: bf.line,
              column: null, // BaselineFinding has no column
              message: bf.message,
              fingerprint: bf.fingerprint,
            ),
          )
          .toList();

      final payload = ReportPayload(
        findings: mappedFindings,
        projectRoot: projectRoot,
        rulesetVersion: baseline.rulesetVersion,
        toolVersion: loamVersion,
        isTty: stdout.hasTerminal,
      );

      // Emit baseline header so the user knows this is the frozen state.
      final count = baseline.findings.length;
      stdout.writeln(
        'loam baseline: $count finding${count == 1 ? '' : 's'} '
        '(${baseline.rulesetVersion}, schemaVersion=${baseline.schemaVersion})',
      );

      // Render the frozen findings via the reporter (same rendering path as scan).
      stdout.write(reporter.render(payload));
    } on BaselineException catch (e) {
      stderr.writeln('loam baseline: ${e.message}');
      return 1;
    }
    return 0;
  }
}

// ---------------------------------------------------------------------------
// Shared helper: load loam.yaml config for the given project root.
//
// Missing file → LoamConfig.defaults() (Zero-Config is the Normalfall).
// Syntax error or unknown ruleId → propagates ConfigLoadException so
// commands can surface a clear message without a raw stacktrace.
// ---------------------------------------------------------------------------

Future<LoamConfig> _loadConfig(String projectRoot) async {
  return ConfigLoader.load(
    projectRoot,
    knownRuleIds: AnalysisRunner.fullRegistryIds.toSet(),
  );
}
