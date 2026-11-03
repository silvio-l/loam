import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:loam/src/architecture/layer_detector.dart';
import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/changed/changed_files.dart';
import 'package:loam/src/command/loam_command.dart';
import 'package:loam/src/command/target_root_resolver.dart';
import 'package:loam/src/complexity/function_complexity_collector.dart';
import 'package:loam/src/complexity/health_score.dart';
import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/config/config_scaffold.dart';
import 'package:loam/src/config/loam_config.dart' show LoamConfig;
import 'package:loam/src/gate/gate_engine.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/loader/sdk_locator.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/progress/progress_sink.dart';
import 'package:loam/src/recommendation/recommendation_engine.dart';
import 'package:loam/src/report/browser_launcher.dart';
import 'package:loam/src/report/html_reporter.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/reporter_dispatch.dart';
import 'package:loam/src/rules/rule_profile.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:loam/src/timing/phase_timer.dart';
import 'package:loam/src/timing/run_watchdog.dart';
import 'package:loam/src/update/auto_update.dart';
import 'package:loam/src/update/install_channel.dart';
import 'package:loam/src/update/update_policy.dart';
import 'package:loam/src/update/update_runtime.dart';
import 'package:loam/src/update/update_state.dart';
import 'package:loam/src/version.dart';
import 'package:loam/src/version_report.dart';
import 'package:loam/src/watch/watch_runner.dart';
import 'package:loam/src/watch/watch_session.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

/// loam.dev CLI entrypoint (command: `loam`).
///
/// Wires the full command surface — scan, health, gate, baseline, a11y, slop
/// and init are live; fix is a stub (coming soon).
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
        ..addCommand(_WatchCommand())
        ..addCommand(_HealthCommand())
        ..addCommand(_GateCommand())
        ..addCommand(_BaselineCommand())
        ..addCommand(_SlopCommand())
        ..addCommand(_A11yCommand())
        ..addCommand(_InitCommand())
        ..addCommand(_FixCommand())
        ..addCommand(_UpdateWorkerCommand());

  runner.argParser
    ..addOption(
      'format',
      allowed: ['human', 'sarif', 'json', 'markdown', 'html', 'agent'],
      defaultsTo: 'human',
      help: 'Output format.',
      allowedHelp: {
        'human': 'Human-readable text (default).',
        'sarif': 'SARIF 2.1 JSON (CI/tooling).',
        'json': 'Machine-readable JSON (agent/tooling integration).',
        'markdown': 'Markdown report (PR/docs embedding, agent/LLM pipelines).',
        'agent':
            'Compact list of the highest-impact findings, capped by '
            '--max-findings; says how many were left out.',
        'html':
            'Self-contained HTML report. Written to a file '
            '(default loam-report.html, override with --output) and opened '
            'in the default browser when run interactively.',
      },
    )
    ..addOption(
      'max-findings',
      valueHelp: 'n',
      help:
          'Cap on the findings listed by --format agent (default 20, highest '
          'impact first; 0 = all). Other formats always list everything.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help:
          'Write the report to this file instead of stdout. '
          'For --format html the report is always written to a file '
          '(default loam-report.html) — this overrides the path.',
      defaultsTo: null,
    )
    ..addFlag(
      'no-open',
      negatable: false,
      help:
          'Do not open the HTML report in the browser. '
          'Auto-open is already suppressed for piped output and under CI.',
    )
    ..addFlag(
      'no-update-check',
      negatable: false,
      help:
          'Skip the update check and the automatic update for this run. '
          'See also: LOAM_NO_UPDATE_CHECK env var and '
          'update_check: false in loam.yaml.',
    )
    ..addFlag(
      'version',
      negatable: false,
      help:
          'Print the running version, install channel and executable path, '
          'then exit. Use this to confirm an upgrade actually took effect.',
    )
    ..addFlag(
      'timing',
      negatable: false,
      help:
          'Print wall-clock time per phase (setup, resolve, rules, '
          'suppression, update-check; report for scan) and per rule to '
          'stderr after the run. '
          'stdout stays unchanged.',
    )
    ..addOption(
      'timeout',
      valueHelp: 'duration',
      help:
          'Abort the run when it takes longer than this (default 10m). '
          'Seconds, or a number with s, m or h (90s, 10m, 1h); 0 or off '
          'disables the limit. Also settable via LOAM_TIMEOUT; the flag wins. '
          'On expiry loam prints the running phase and rule to stderr and '
          'exits with 124 (not 1, so a hook can tell it from a red gate).',
    )
    ..addFlag(
      'no-cache',
      negatable: false,
      help:
          'Do not keep the analyzer\'s summary store in .dart_tool/loam/ '
          'between runs (it speeds up resolving; results are the same '
          'either way). See also: cache: false in loam.yaml.',
    )
    ..addFlag(
      'no-progress',
      negatable: false,
      help:
          'Suppress the live progress bar during scan. '
          'Progress is already off when output is piped/redirected or under CI. '
          'See also: LOAM_NO_PROGRESS env var.',
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
  final maxFindingsRaw = topLevelResults['max-findings'] as String?;
  if (maxFindingsRaw != null && ((int.tryParse(maxFindingsRaw) ?? -1) < 0)) {
    stderr.writeln(
      'loam: --max-findings expects a whole number >= 0 (0 = all), '
      'got "$maxFindingsRaw".',
    );
    return 64;
  }
  // --version short-circuit: print version + install channel + resolved
  // executable path, then exit 0 before any command dispatch. This is the
  // anchor an agent uses to confirm an upgrade landed on the binary actually
  // on PATH (the footer and this line share the single `loamVersion` source).
  if (topLevelResults.flag('version')) {
    stdout.writeln(formatVersionInfo(InstallInfo.current()));
    return 0;
  }

  final noUpdateCheckFlag = topLevelResults.flag('no-update-check');
  _lastLoadedConfig = null; // run() is re-entered in-process by tests.
  _noCacheFlag = topLevelResults.flag('no-cache');
  final commandName = topLevelResults.command?.name;
  if (commandName == kUpdateWorkerCommand) {
    return await runner.runCommand(topLevelResults) ?? 0;
  }

  // Auto-update, foreground half (ADR-0004, issue #9): never touches the
  // network and never waits. Before the command it reports the last
  // background install once; after it, it starts the next background check
  // when one is due. Everything goes to stderr and never changes the exit code.
  final updates = _AutoUpdateGlue(noUpdateCheckFlag: noUpdateCheckFlag);
  updates.announce();

  // Time limit (issue #31): a watchdog isolate ends a hanging run with exit
  // 124 and a message naming the phase/rule. It needs the phase events, so a
  // timer exists whenever either --timing or the limit is on.
  final Duration? limit;
  try {
    limit = resolveRunTimeout(
      flag: topLevelResults.option('timeout'),
      env: Platform.environment[kRunTimeoutEnv],
    );
  } on FormatException catch (e) {
    stderr.writeln('loam: ${e.message}');
    return 64;
  }
  // `watch` is meant to run until stopped; a time limit would end it by design.
  final watchdog = await RunWatchdog.start(
    topLevelResults.command?.name == 'watch' ? null : limit,
  );
  final timing = topLevelResults.flag('timing');
  // --timing: one timer per invocation; the loader and runner report into it.
  // Reset to null in the `finally` below, so no state outlives this run().
  final PhaseTimer? timer = PhaseTimer.active = (timing || watchdog != null)
      ? PhaseTimer.wallClock(
          onEvent: watchdog == null
              ? null
              : (label, depth, {required started}) =>
                    watchdog.event(label, depth, started: started),
        )
      : null;

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
  } on SdkResolutionException catch (e) {
    // No usable Dart SDK in this environment (e.g. only Flutter's bin/ on PATH,
    // where `dart` is a wrapper and AnalysisContextCollection would crash with a
    // raw PathNotFoundException). Emit the actionable, stacktrace-free guidance
    // and a non-zero exit code (78 = EX_CONFIG — an environment misconfig).
    stderr.writeln(e.message);
    return 78;
  } finally {
    // Process-wide state must not leak into later in-process run() calls
    // or tests; the timer itself stays reachable through the local below.
    PhaseTimer.active = null;
    watchdog?.stop();
  }

  final stopUpdateCheck = timer?.begin('update-check');
  await updates.afterCommand(warnOnPin: commandName != 'gate');
  stopUpdateCheck?.call();
  if (timing && timer != null) stderr.write(timer.render());
  return code;
}

/// Wires the auto-update into the CLI run. Every step is best-effort: an
/// error is swallowed so the update machinery can never change a result.
class _AutoUpdateGlue {
  _AutoUpdateGlue({required this.noUpdateCheckFlag});

  final bool noUpdateCheckFlag;
  final UpdateRuntime _runtime = UpdateRuntime();
  final UpdateStateStore _store = FileUpdateStateStore();

  AutoUpdateCoordinator get _coordinator => AutoUpdateCoordinator(
    current: Version.parse(loamVersion),
    currentRuleIds: AnalysisRunner.fullRegistryIds,
    upgradeCommand: _runtime.install.upgradeCommand,
    store: _store,
    spawnWorker: _runtime.spawnWorker,
  );

  /// The config that decides the update mode: the one the command loaded
  /// (it sees the analysed project's `loam.yaml`), else the one around cwd.
  Future<LoamConfig> _config() async {
    final loaded = _lastLoadedConfig;
    if (loaded != null) return loaded;
    try {
      return await _loadConfig(Directory.current.path);
    } on Object {
      return const LoamConfig.defaults();
    }
  }

  Future<UpdateMode> _mode() async {
    final config = await _config();
    return decideUpdateMode(
      env: Platform.environment,
      noUpdateCheckFlag: noUpdateCheckFlag,
      configUpdateCheck: config.updateCheck,
      configAutoUpdate: config.autoUpdate,
      requiredVersion: config.requiredVersion,
      canSelfUpdate: _runtime.canUpdateItself,
    );
  }

  void announce() {
    try {
      if (noUpdateCheckFlag ||
          Platform.environment.containsKey('LOAM_NO_UPDATE_CHECK') ||
          isCiEnvironment(Platform.environment)) {
        return;
      }
      _coordinator.takeAnnouncements().forEach(stderr.writeln);
      // loam-ignore: slop-empty-catch – the update report is optional and must never affect the run or its exit code (ADR-0004).
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> afterCommand({required bool warnOnPin}) async {
    try {
      final config = await _config();
      final pin = config.requiredVersion;
      final current = Version.parse(loamVersion);
      if (warnOnPin && pin != null && pinViolation(current, pin)) {
        stderr.writeln(formatPinViolation(current, pin));
      }
      final lines = await _coordinator.afterRun(await _mode());
      lines.forEach(stderr.writeln);
      // loam-ignore: slop-empty-catch – update errors are non-fatal; the update path is optional and must never affect the exit code (ADR-0004).
    } catch (_) {
      // Best-effort only.
    }
  }
}

/// Hidden sub-command: the background half of the auto-update. Started
/// detached by a normal run; checks pub.dev and, with `--install`, installs a
/// newer release for this install channel. Not meant to be run by hand.
class _UpdateWorkerCommand extends Command<int> {
  _UpdateWorkerCommand() {
    argParser.addFlag('install', negatable: false);
  }

  @override
  final String name = kUpdateWorkerCommand;
  @override
  final String description = 'Background update worker (internal).';
  @override
  bool get hidden => true;

  @override
  Future<int> run() async {
    try {
      await UpdateRuntime().runWorker(
        installAllowed: argResults?.flag('install') ?? false,
        current: Version.parse(loamVersion),
        currentRuleIds: AnalysisRunner.fullRegistryIds,
      );
      // loam-ignore: slop-empty-catch – the detached worker has no terminal; a failure is recorded in the update state or retried on the next due run.
    } catch (_) {
      // Nothing to report to: the worker runs detached.
    }
    return 0;
  }
}

/// Full audit: runs all active rules across the whole project
/// (baseline-independent). Driven by [LoamCommand] base.
///
/// Renders findings via the [Reporter] selected by `--format` (default: human).
/// Exit-code semantics: 1 when any findings are present, 0 when clean.
/// The reporter is a pure renderer — it has no influence on the exit code
/// (ADR 0001).
class ScanCommand extends LoamCommand {
  ScanCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'p',
        help:
            'Root directory of the Dart project to analyse. '
            'Overrides the positional [path] argument when both are given. '
            'Defaults to the current working directory.',
        defaultsTo: null,
      )
      ..addFlag(
        'no-a11y',
        negatable: false,
        help:
            'Exclude accessibility-category rules from this scan. '
            'CLI override for `a11y: false` in loam.yaml. '
            'Use `loam a11y` to run accessibility checks in isolation.',
      );
    addChangedOptions(argParser);
  }

  @override
  final String name = 'scan';
  @override
  String get invocation => 'loam scan [path] [options]';
  @override
  final String description =
      'Full audit: run all active rules across the whole project '
      '(baseline-independent).\n\n'
      '[path] — optional positional path to the project root '
      '(defaults to the current directory). '
      '-p/--project-root overrides [path] when both are given.';

  @override
  Future<int> run() async {
    // Resolve project root via shared resolver (positional or --project-root).
    final rootResult = TargetRootResolver.resolve(argResults);
    if (rootResult is RootUsageError) {
      stderr.writeln(rootResult.message);
      return 64; // EX_USAGE
    }
    final projectRoot = (rootResult as ResolvedRoot).root;

    // --staged / --since / --changed: resolve first so a usage problem fails
    // before the (slow) analysis. Null = whole project.
    final scope = await _resolveChangedScope(argResults, projectRoot);
    if (scope.error != null) {
      stderr.writeln(scope.error);
      return 64; // EX_USAGE
    }
    final changedFiles = scope.files;

    // Resolve the format from the global --format option.
    final format = (globalResults?['format'] as String?) ?? 'human';

    // Load project config (loam.yaml) — missing file returns defaults.
    final yamlConfig = await _loadConfig(projectRoot);

    // --no-a11y CLI flag overrides the loam.yaml a11y setting.
    // Precedence: --no-a11y (CLI) > a11y: false (loam.yaml) > default (on).
    final noA11y = argResults?.flag('no-a11y') ?? false;
    final config = noA11y && yamlConfig.includeA11y
        ? LoamConfig(
            ruleToggles: yamlConfig.ruleToggles,
            ignoreGlobs: yamlConfig.ignoreGlobs,
            sourceDirs: yamlConfig.sourceDirs,
            updateCheck: yamlConfig.updateCheck,
            includeA11y: false,
            cache: yamlConfig.cache,
          )
        : yamlConfig;

    // Progress setup — shared seam (LoamCommand.resolveProgress), wired
    // identically across every analysing command (scan, gate, baseline, slop,
    // a11y, health).
    final progress = resolveProgress();
    final showProgress = progress.showProgress;
    final progressSink = progress.sink;
    final scanStopwatch = Stopwatch()..start();

    // For HTML format: load the project once and share it between the
    // AnalysisRunner (findings) and FunctionComplexityCollector (health sidecar).
    // This guarantees the badge value matches `loam health` for the same project
    // (same collector path, no second load, no drift — AC3).
    //
    // For all other formats: delegate to AnalysisRunner.analyze() as before (no
    // change to their code path → byte-identical output guaranteed — AC2).
    AnalysisOutcome outcome;
    final Reporter reporter;

    if (format == 'html') {
      // Single project load shared by both consumers.
      // Pass the progress sink so the load phase is tracked.
      final root = p.normalize(p.absolute(projectRoot));
      final loadResult = await const ProjectLoader().load(
        root,
        progressSink: progressSink,
        cacheDirectory: _analyzerCacheFor(root, config),
      );

      // Outcome via shared load result — same as before, just no second load.
      // Pass the progress sink so the analysis phase is tracked.
      outcome = AnalysisRunner(
        config: config,
        progressSink: progressSink,
        analyzerCacheDirectory: _analyzerCacheFor(root, config),
      ).analyzeWithLoadResult(root, loadResult);

      // Health-Score sidecar: same collector as `loam health` (AC3 — no drift).
      final functions = const FunctionComplexityCollector().collect(
        loadResult,
        root,
        sourceDirs: config.sourceDirs,
      );
      final healthReport = const HealthScore().compute(
        functions,
        findings: outcome.findings,
        linesAnalyzed: outcome.stats.linesAnalyzed,
      );

      // HtmlReporter with the sidecar — only this format receives health data.
      reporter = HtmlReporter(healthSidecar: healthReport);
    } else {
      // Non-HTML path: AnalysisRunner.analyze() handles both load and analysis
      // phases internally, forwarding the progress sink to ProjectLoader.
      outcome = await AnalysisRunner(
        config: config,
        progressSink: progressSink,
        analyzerCacheDirectory: _analyzerCacheFor(projectRoot, config),
      ).analyze(projectRoot);
      // Resolve reporter — FormatNotImplementedError surfaces as a usage error.
      try {
        reporter = reporterFor(format);
      } on FormatNotImplementedError catch (e) {
        stderr.writeln(e.toString());
        return 64; // EX_USAGE
      }
    }

    // The analysis above was project-wide; only the report is narrowed.
    if (changedFiles != null) {
      outcome = AnalysisOutcome(
        findings: filterFindingsToFiles(outcome.findings, changedFiles),
        suppressedCount: outcome.suppressedCount,
        stats: outcome.stats,
        stackProfile: outcome.stackProfile,
        suppressionAudit: outcome.suppressionAudit,
      );
      stderr.writeln(_changedScopeNote(name, changedFiles.length));
    }

    // Diagnostic line: printed to stdout for human-readable output only.
    // Structured formats (json/sarif/html/markdown) must not have extra text
    // mixed into their output.
    if (format == 'human') {
      stdout.writeln(_formatStackDiagnostic(outcome.stackProfile));
    }

    final payload = ReportPayload(
      findings: outcome.findings,
      projectRoot: projectRoot,
      rulesetVersion: AnalysisRunner.rulesetVersionForConfig(config),
      toolVersion: loamVersion,
      isTty: stdout.hasTerminal,
      maxFindings: maxFindings,
      suppressedCount: outcome.suppressedCount,
      suppressionAudit: outcome.suppressionAudit,
      stats: outcome.stats,
      sourceDirs: config.sourceDirs,
      recommendations: const RecommendationEngine().recommend(outcome.findings),
    );

    await _emitReport(
      rendered: PhaseTimer.time('report', () => reporter.render(payload)),
      format: format,
      commandName: name,
      outputOption: outputPath,
      noOpen: noOpen,
    );

    // Success summary on stderr — only when progress was shown (interactive TTY).
    // Goes to stderr so stdout (structured formats) stays byte-identical.
    if (showProgress) {
      scanStopwatch.stop();
      final elapsed = scanStopwatch.elapsed;
      final durationStr = elapsed.inSeconds >= 1
          ? '${elapsed.inSeconds}s'
          : '${elapsed.inMilliseconds}ms';
      final n = outcome.findings.length;
      stderr.writeln(
        'loam scan: $n finding${n == 1 ? '' : 's'} in $durationStr',
      );
    }

    return outcome.findings.isNotEmpty ? 1 : 0;
  }
}

/// Watch mode for local iteration: runs the full audit once, then re-runs it
/// after every change to a Dart file (or `pubspec.yaml`, `analysis_options.yaml`,
/// `loam.yaml`) and prints what changed. See [runWatch] / [WatchSession].
///
/// Every run analyses the whole project (the analyzer's summary store on disk
/// keeps it fast), so cross-file findings are never lost. Baseline-independent
/// like `scan`. Runs until SIGINT/SIGTERM, then exits 0.
class _WatchCommand extends LoamCommand {
  _WatchCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'p',
        help:
            'Root directory of the Dart project to watch. '
            'Overrides the positional [path] argument when both are given. '
            'Defaults to the current working directory.',
        defaultsTo: null,
      )
      ..addOption(
        'debounce',
        valueHelp: 'ms',
        defaultsTo: '${kDefaultWatchDebounce.inMilliseconds}',
        help:
            'Quiet period after the last file change before a run starts, '
            'in milliseconds (0-60000).',
      );
  }

  @override
  final String name = 'watch';
  @override
  String get invocation => 'loam watch [path] [options]';
  @override
  final String description =
      'Watch mode: run the full audit, then re-run it after every change to '
      'a Dart file and print what is new or resolved (stop with Ctrl+C).\n\n'
      '[path] — optional positional path to the project root '
      '(defaults to the current directory). '
      '-p/--project-root overrides [path] when both are given.';

  @override
  Future<int> run() async {
    final rootResult = TargetRootResolver.resolve(argResults);
    if (rootResult is RootUsageError) {
      stderr.writeln(rootResult.message);
      return 64; // EX_USAGE
    }
    final projectRoot = p.normalize(
      p.absolute((rootResult as ResolvedRoot).root),
    );

    if (format != 'human') {
      stderr.writeln(
        'loam watch: only --format human is supported '
        '(got "$format"); use `loam scan --format $format` for a single run.',
      );
      return 64;
    }
    final debounceMs = int.tryParse(argResults?.option('debounce') ?? '');
    if (debounceMs == null || debounceMs < 0 || debounceMs > 60000) {
      stderr.writeln(
        'loam watch: --debounce expects whole milliseconds between 0 and '
        '60000.',
      );
      return 64;
    }

    // Same config for every run would hide edits to loam.yaml: load per run.
    Future<List<Finding>> analyze() async {
      final config = await _loadConfig(projectRoot);
      final outcome = await AnalysisRunner(
        config: config,
        analyzerCacheDirectory: _analyzerCacheFor(projectRoot, config),
      ).analyze(projectRoot);
      return outcome.findings;
    }

    String renderFull(List<Finding> findings) {
      final config = _lastLoadedConfig ?? const LoamConfig.defaults();
      return reporterFor('human').render(
        ReportPayload(
          findings: findings,
          projectRoot: projectRoot,
          rulesetVersion: AnalysisRunner.rulesetVersionForConfig(config),
          toolVersion: loamVersion,
          isTty: stdout.hasTerminal,
          sourceDirs: config.sourceDirs,
          recommendations: const RecommendationEngine().recommend(findings),
        ),
      );
    }

    // First signal: finish the running analysis and leave cleanly. A second
    // one means "now": exit without waiting.
    final stopRequests = StreamController<void>.broadcast();
    var signals = 0;
    void onSignal(ProcessSignal _) {
      if (++signals > 1) exit(130);
      stopRequests.add(null);
    }

    final subscriptions = <StreamSubscription<ProcessSignal>>[
      ProcessSignal.sigint.watch().listen(onSignal),
    ];
    try {
      subscriptions.add(ProcessSignal.sigterm.watch().listen(onSignal));
      // loam-ignore: slop-empty-catch – SIGTERM cannot be watched on Windows; Ctrl+C (SIGINT) still stops the watch.
    } on SignalException {
      // Nothing to do.
    }

    var watcherErrorShown = false;
    try {
      return await runWatch(
        root: projectRoot,
        changes: Directory(projectRoot)
            .watch(recursive: true)
            .map((event) => event.path)
            .handleError((Object error) {
              // A dead file watcher (e.g. inotify limit) must not fail silently.
              if (!watcherErrorShown) {
                watcherErrorShown = true;
                stderr.writeln(
                  'loam watch: file watcher error ($error) - changes may be '
                  'missed; restart watch if no reruns happen.',
                );
              }
            }),
        analyze: analyze,
        renderFull: renderFull,
        out: stdout,
        err: stderr,
        stopRequests: stopRequests.stream,
        debounce: Duration(milliseconds: debounceMs),
      );
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await stopRequests.close();
    }
  }
}

/// Project health score: cyclomatic/cognitive complexity distribution view.
///
/// Loads the project via [ProjectLoader], measures every named executable in
/// `lib/` with [FunctionComplexityCollector], aggregates via [HealthScore],
/// and renders Score + Grade + Hotspot table via a command-own terminal
/// renderer — **not** the [Reporter] pipeline.
///
/// Exit-code semantics: this is a REPORT command, not a gate.
/// - Exit 0 on success (even when the score is low — gating stays `loam gate`).
/// - Exit 64 (EX_USAGE) on a usage error (broken `--project-root`).
///
/// Toggle note: a `loam.yaml`-disabled `complexity-hotspots` toggle does NOT
/// affect this command — `health` always measures, regardless of the rule
/// registry. The codegen exclusion is applied by the collector itself.
class _HealthCommand extends LoamCommand {
  _HealthCommand() {
    argParser.addOption(
      'project-root',
      abbr: 'p',
      help:
          'Root directory of the Dart project to analyse. '
          'Overrides the positional [path] argument when both are given. '
          'Defaults to the current working directory.',
      defaultsTo: null,
    );
  }

  @override
  final String name = 'health';
  @override
  String get invocation => 'loam health [path] [options]';
  @override
  final String description =
      'Project health score: cyclomatic/cognitive complexity distribution view.\n\n'
      '[path] — optional positional path to the project root '
      '(defaults to the current directory). '
      '-p/--project-root overrides [path] when both are given.';

  @override
  Future<int> run() async {
    // Resolve project root via shared resolver (positional or --project-root).
    final rootResult = TargetRootResolver.resolve(argResults);
    if (rootResult is RootUsageError) {
      stderr.writeln(rootResult.message);
      return 64; // EX_USAGE
    }
    final projectRoot = (rootResult as ResolvedRoot).root;

    // Progress setup — shared seam (LoamCommand.resolveProgress). The single
    // ProjectLoader.load() below feeds both the health measurement and the
    // findings axis, so one progressSink already covers both phases — no
    // second/conflicting renderer instance.
    final progress = resolveProgress();
    final progressSink = progress.sink;

    // Load config for the source-dir scope (loam.yaml); missing → defaults.
    final config = await _loadConfig(projectRoot);

    // Load the project — ProjectLoader never throws.
    final loadResult = await const ProjectLoader().load(
      projectRoot,
      progressSink: progressSink,
      cacheDirectory: _analyzerCacheFor(projectRoot, config),
    );

    // Collect complexity measurements from the configured source dirs (codegen
    // exclusion is inside the collector — no toggle check needed here).
    final functions = const FunctionComplexityCollector().collect(
      loadResult,
      projectRoot,
      sourceDirs: config.sourceDirs,
    );

    // Findings + line count for the composite score's findings axis — shares
    // the same loaded project (no second load, same as the HTML sidecar path
    // above — AC: no drift between `loam health` and the HTML badge).
    //
    // Rule toggles are deliberately NOT forwarded here: `health` always
    // measures with the full rule registry, regardless of `loam.yaml`
    // (see the toggle note in this command's class doc) — only `sourceDirs`,
    // `ignoreGlobs`, and `includeA11y` carry over from the loaded config.
    final measurementConfig = LoamConfig(
      ruleToggles: const {},
      ignoreGlobs: config.ignoreGlobs,
      sourceDirs: config.sourceDirs,
      updateCheck: config.updateCheck,
      includeA11y: config.includeA11y,
      cache: config.cache,
    );
    final outcome = AnalysisRunner(
      config: measurementConfig,
      progressSink: progressSink,
      analyzerCacheDirectory: _analyzerCacheFor(projectRoot, measurementConfig),
    ).analyzeWithLoadResult(projectRoot, loadResult);

    // Aggregate into a health report.
    final report = const HealthScore().compute(
      functions,
      findings: outcome.findings,
      linesAnalyzed: outcome.stats.linesAnalyzed,
    );

    // Render via command-own terminal renderer (not the Reporter pipeline).
    _renderHealthReport(report, projectRoot, stdout);

    return 0; // Health is a report command — exit 0 even on low score.
  }
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
/// **Rule profile** (`--profile core|strict`, `profile:` in loam.yaml, default
/// `core`): only rules of the active profile can turn the gate red; findings
/// of other rules are shown as a hint. `baseline.json` is profile-independent.
///
/// Findings are rendered via the [Reporter] selected by `--format`.
/// The Gate-summary line and exit code are determined exclusively by
/// [GateEngine] — the reporter is a pure renderer (ADR 0001).
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
      ..addFlag(
        'strict-baseline',
        help:
            'Ratchet mode: stale baseline entries (findings that no longer '
            'occur) turn the gate red. Overrides `strict_baseline` in '
            'loam.yaml; default off — stale entries are only reported. '
            'Clean up with `loam baseline --prune`.',
      )
      ..addOption(
        'profile',
        allowed: ['core', 'strict'],
        allowedHelp: {
          'core':
              'Only rules with a near-zero false-positive rate block '
              '(default).',
          'strict': 'Every rule blocks, including heuristic ones.',
        },
        help:
            'Which rules may block the gate; other rules show up as a hint. '
            'Overrides profile: in loam.yaml. Does not touch baseline.json.',
      )
      ..addOption(
        'project-root',
        abbr: 'p',
        help:
            'Root directory of the Dart project to analyse. '
            'Overrides the positional [path] argument when both are given. '
            'Defaults to the current working directory.',
        defaultsTo: null,
      );
    addChangedOptions(argParser);
  }

  @override
  final String name = 'gate';
  @override
  String get invocation => 'loam gate [path] [options]';
  @override
  final String description =
      'CI gate: baseline/ratchet (default) or --absolute threshold mode.\n\n'
      '[path] — optional positional path to the project root '
      '(defaults to the current directory). '
      '-p/--project-root overrides [path] when both are given.';

  @override
  Future<int> run() async {
    // Resolve project root via shared resolver (positional or --project-root).
    final rootResult = TargetRootResolver.resolve(argResults);
    if (rootResult is RootUsageError) {
      stderr.writeln(rootResult.message);
      return 64; // EX_USAGE
    }
    final projectRoot = (rootResult as ResolvedRoot).root;
    final absoluteMode = argResults?.flag('absolute') ?? false;
    if (absoluteMode && (argResults?.wasParsed('strict-baseline') ?? false)) {
      stderr.writeln(
        'loam gate: --strict-baseline needs the baseline and cannot be '
        'combined with --absolute.',
      );
      return 64; // EX_USAGE
    }

    final scope = await _resolveChangedScope(argResults, projectRoot);
    if (scope.error != null) {
      stderr.writeln(scope.error);
      return 64; // EX_USAGE
    }
    final changedFiles = scope.files;
    if (changedFiles != null) {
      stderr.writeln(_changedScopeNote(name, changedFiles.length));
    }

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

    // Version pin (required_version): a gate run on the wrong loam version
    // would judge the code with a different ruleset, so it stops instead of
    // reporting a result (78 = EX_CONFIG). Other commands only warn.
    final pin = config.requiredVersion;
    final running = Version.parse(loamVersion);
    if (pin != null && pinViolation(running, pin)) {
      stderr.writeln(formatPinViolation(running, pin));
      stderr.writeln('loam gate: stopped — the loam version does not match.');
      return 78;
    }

    // Precedence: --profile (CLI) > profile: (loam.yaml) > core.
    final profile = RuleProfile.resolve(
      cli: RuleProfile.tryParse(argResults?['profile'] as String? ?? ''),
      config: config.profile,
    );

    // Progress setup — shared seam (LoamCommand.resolveProgress). Visible on
    // a manual local run; the CI-env check inside shouldShowProgress turns it
    // off automatically under CI.
    final progressSink = resolveProgress().sink;

    if (absoluteMode) {
      return _runAbsolute(
        projectRoot,
        reporter,
        config,
        progressSink,
        changedFiles,
        profile,
      );
    }
    final strictBaseline = (argResults?.wasParsed('strict-baseline') ?? false)
        ? argResults!.flag('strict-baseline')
        : config.strictBaseline;
    return _runRatchet(
      projectRoot,
      reporter,
      config,
      progressSink,
      changedFiles,
      profile,
      strictBaseline,
    );
  }

  /// Hint for findings outside the active profile (never affects the exit code).
  void _writeAdvisory(GateResult result, RuleProfile profile) {
    if (result.advisoryCount == 0) return;
    final n = result.advisoryCount;
    _noteSink(format).writeln(
      'loam gate: $n Hinweis${n == 1 ? '' : 'e'} aus Rules außerhalb des '
      'Profils ${profile.name} (nicht blockierend; '
      '`--profile strict` lässt sie blocken).',
    );
  }

  Future<int> _runAbsolute(
    String projectRoot,
    Reporter reporter,
    LoamConfig config,
    ProgressSink progressSink,
    Set<String>? changedFiles,
    RuleProfile profile,
  ) async {
    final outcome = await AnalysisRunner(
      config: config,
      progressSink: progressSink,
      analyzerCacheDirectory: _analyzerCacheFor(projectRoot, config),
    ).analyze(projectRoot);
    var findings = outcome.findings;
    if (changedFiles != null) {
      findings = filterFindingsToFiles(findings, changedFiles);
    }
    final result = const GateEngine().evaluate(
      mode: GateMode.absolute,
      findings: findings,
      profile: profile,
    );

    // Render findings via reporter (pure display — does not influence exit code).
    if (findings.isNotEmpty || _isDocumentFormat(format)) {
      final payload = ReportPayload(
        findings: findings,
        projectRoot: projectRoot,
        rulesetVersion: AnalysisRunner.rulesetVersionForConfig(config),
        toolVersion: loamVersion,
        isTty: stdout.hasTerminal,
        maxFindings: maxFindings,
        sourceDirs: config.sourceDirs,
        recommendations: const RecommendationEngine().recommend(findings),
      );
      await _emitReport(
        rendered: reporter.render(payload),
        format: format,
        commandName: name,
        outputOption: outputPath,
        noOpen: noOpen,
      );
    }

    // Gate-summary line comes exclusively from GateEngine (pure renderer, ADR 0001).
    final count = result.newCount;
    _noteSink(format).writeln(
      'loam gate --absolute: $count finding${count == 1 ? '' : 's'} '
      '— ${result.passed ? 'grün' : 'rot'}.',
    );
    _writeAdvisory(result, profile);

    // Suppression audit: per-rule counts and directive warnings on stderr —
    // visible in CI logs, never part of the gate decision (warn, don't abort).
    for (final line in outcome.suppressionAudit.toSummaryLines()) {
      stderr.writeln('loam gate: $line');
    }

    return result.exitCode;
  }

  Future<int> _runRatchet(
    String projectRoot,
    Reporter reporter,
    LoamConfig config,
    ProgressSink progressSink,
    Set<String>? changedFiles,
    RuleProfile profile,
    bool strictBaseline,
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
      return 66; // EX_NOINPUT: not a red gate, the gate could not run.
    }

    // AC4: rulesetVersion mismatch → warning on stderr, diff continues normally.
    final currentVersion = AnalysisRunner.rulesetVersionForConfig(config);
    final rulesetChanged = baseline.rulesetVersion != currentVersion;
    if (rulesetChanged) {
      stderr.writeln(
        'loam gate: warning — baseline rulesetVersion '
        '(${baseline.rulesetVersion}) differs from current '
        '($currentVersion). '
        'Consider refreshing with `loam baseline --update`.',
      );
    }

    if (baseline.isLegacyScheme) {
      stderr.writeln(
        'loam gate: note — baseline.json uses the legacy fingerprint scheme; '
        'findings are matched transitionally by rule, file and message. '
        'Run `loam baseline --update` once to upgrade it.',
      );
    }

    final outcome = await AnalysisRunner(
      config: config,
      progressSink: progressSink,
      analyzerCacheDirectory: _analyzerCacheFor(projectRoot, config),
    ).analyze(projectRoot);
    var findings = outcome.findings;
    // Diff against the baseline over the whole project, then narrow both the
    // diff and the rendered findings to the selected files (see
    // scopeDiffToFiles for why the order matters).
    var diff = engine.diff(findings, baseline);
    if (changedFiles != null) {
      diff = scopeDiffToFiles(diff, changedFiles);
      findings = filterFindingsToFiles(findings, changedFiles);
    }
    final result = const GateEngine().evaluate(
      mode: GateMode.ratchet,
      diff: diff,
      profile: profile,
      strictStale: strictBaseline,
    );

    // Render current findings (all of them: new + kept) via reporter.
    // The reporter shows what is there now — gate-decision stays in GateEngine.
    // Only render when there are findings to show (avoids empty output noise).
    if (findings.isNotEmpty || _isDocumentFormat(format)) {
      final payload = ReportPayload(
        findings: findings,
        projectRoot: projectRoot,
        rulesetVersion: AnalysisRunner.rulesetVersionForConfig(config),
        toolVersion: loamVersion,
        isTty: stdout.hasTerminal,
        maxFindings: maxFindings,
        baselineDiff: diff,
        sourceDirs: config.sourceDirs,
        recommendations: const RecommendationEngine().recommend(findings),
      );
      await _emitReport(
        rendered: reporter.render(payload),
        format: format,
        commandName: name,
        outputOption: outputPath,
        noOpen: noOpen,
      );
    }

    // AC3: Terse summary line to stdout (neu/eingefroren/gefixt).
    // This line comes exclusively from GateEngine — reporter has no influence
    // on the gate decision or exit code (pure renderer, ADR 0001).
    // A red gate after a ruleset change is explained, not left unexplained:
    // the new findings may come from added rules (e.g. after a loam update).
    if (rulesetChanged && !result.passed) {
      stderr.writeln(
        'loam gate: the ruleset differs from the baseline, so new findings '
        'may come from changed rules (for example after a loam update), not '
        'from your code. Review them, then run `loam baseline --update`.',
      );
    }

    _noteSink(format).writeln(
      'loam gate: ${result.newCount} neu, '
      '${result.keptCount} eingefroren, '
      '${result.fixedCount} gefixt '
      '— ${result.passed ? 'grün' : 'rot'}.',
    );
    _writeAdvisory(result, profile);

    // Stale baseline entries (the "gefixt" count): name them per rule so a fix
    // cannot slip back in unnoticed. With --changed/--staged/--since only the
    // selected files count; `baseline --prune` is always project-wide.
    final stale = diff.staleByRule;
    if (stale.isNotEmpty) {
      final perRule = stale.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      final n = result.fixedCount;
      stderr.writeln(
        'loam gate: $n stale baseline entr${n == 1 ? 'y' : 'ies'} '
        '($perRule) — no longer occurring; remove with '
        '`loam baseline --prune`.'
        '${strictBaseline ? ' Strict baseline: the gate is red.' : ''}',
      );
    }

    // Suppression audit: per-rule counts and directive warnings on stderr —
    // visible in CI logs, never part of the gate decision (warn, don't abort).
    for (final line in outcome.suppressionAudit.toSummaryLines()) {
      stderr.writeln('loam gate: $line');
    }

    return result.exitCode;
  }
}

/// AI-slop audit: runs slop-focused rules across the whole project.
///
/// Currently runs [SlopUnjustifiedIgnoreRule] (and any future slop rules) via
/// [AnalysisRunner] with `categoryFilter: RuleCategory.slop`. Wired analogously
/// to [_A11yCommand].
///
/// Exit code `1` when any slop findings are present; `0` when clean.
/// The reporter is a pure renderer — it has no influence on the exit code
/// (ADR 0001).
class _SlopCommand extends LoamCommand {
  _SlopCommand() {
    argParser.addOption(
      'project-root',
      abbr: 'p',
      help:
          'Root directory of the Dart project to analyse. '
          'Overrides the positional [path] argument when both are given. '
          'Defaults to the current working directory.',
      defaultsTo: null,
    );
  }

  @override
  final String name = 'slop';
  @override
  String get invocation => 'loam slop [path] [options]';
  @override
  final String description =
      'AI-slop audit: run slop-focused rules across the whole project.\n\n'
      '[path] — optional positional path to the project root '
      '(defaults to the current directory). '
      '-p/--project-root overrides [path] when both are given.';

  @override
  // loam-ignore: code-duplicates – per-command boilerplate shared with _A11yCommand; each command's run() body is self-contained so that readers understand the command without jumping across the file.
  Future<int> run() async {
    // Resolve project root via shared resolver (positional or --project-root).
    final rootResult = TargetRootResolver.resolve(argResults);
    if (rootResult is RootUsageError) {
      stderr.writeln(rootResult.message);
      return 64; // EX_USAGE
    }
    final projectRoot = (rootResult as ResolvedRoot).root;

    // Resolve the format from the global --format option.
    final format = (globalResults?['format'] as String?) ?? 'human';

    // Load project config (loam.yaml) — missing file returns defaults.
    final config = await _loadConfig(projectRoot);

    // Resolve reporter — FormatNotImplementedError surfaces as a usage error.
    final Reporter reporter;
    try {
      reporter = reporterFor(format);
    } on FormatNotImplementedError catch (e) {
      stderr.writeln(e.toString());
      return 64; // EX_USAGE
    }

    // Progress setup — shared seam (LoamCommand.resolveProgress).
    final progressSink = resolveProgress().sink;

    // Run with slop-category filter only.
    final outcome = await AnalysisRunner(
      config: config,
      categoryFilter: RuleCategory.slop,
      progressSink: progressSink,
      analyzerCacheDirectory: _analyzerCacheFor(projectRoot, config),
    ).analyze(projectRoot);

    // Diagnostic line for human-readable output.
    if (format == 'human') {
      stdout.writeln('loam slop  AI-slop scan');
    }

    final payload = ReportPayload(
      findings: outcome.findings,
      projectRoot: projectRoot,
      rulesetVersion: AnalysisRunner.rulesetVersionForCategory(
        RuleCategory.slop,
        config,
      ),
      toolVersion: loamVersion,
      isTty: stdout.hasTerminal,
      maxFindings: maxFindings,
      suppressedCount: outcome.suppressedCount,
      stats: outcome.stats,
      sourceDirs: config.sourceDirs,
      recommendations: const RecommendationEngine().recommend(outcome.findings),
    );

    await _emitReport(
      rendered: reporter.render(payload),
      format: format,
      commandName: name,
      outputOption: outputPath,
      noOpen: noOpen,
    );

    return outcome.findings.isNotEmpty ? 1 : 0;
  }
}

/// Accessibility audit: runs accessibility-category rules across the whole
/// project.
///
/// Currently no accessibility rules are registered — the command exists to
/// establish the [RuleCategory.accessibility] category seam and to let CI
/// workflows wire `loam a11y` before the first WCAG rules land.
///
/// Exit code `1` when any accessibility findings are present; `0` when clean.
/// The reporter is a pure renderer — it has no influence on the exit code
/// (ADR 0001).
class _A11yCommand extends LoamCommand {
  _A11yCommand() {
    argParser.addOption(
      'project-root',
      abbr: 'p',
      help:
          'Root directory of the Dart project to analyse. '
          'Overrides the positional [path] argument when both are given. '
          'Defaults to the current working directory.',
      defaultsTo: null,
    );
  }

  @override
  final String name = 'a11y';
  @override
  String get invocation => 'loam a11y [path] [options]';
  @override
  final String description =
      'Accessibility audit: run accessibility-focused rules across the whole '
      'project.\n\n'
      '[path] — optional positional path to the project root '
      '(defaults to the current directory). '
      '-p/--project-root overrides [path] when both are given.';

  @override
  Future<int> run() async {
    // Resolve project root via shared resolver (positional or --project-root).
    final rootResult = TargetRootResolver.resolve(argResults);
    if (rootResult is RootUsageError) {
      stderr.writeln(rootResult.message);
      return 64; // EX_USAGE
    }
    final projectRoot = (rootResult as ResolvedRoot).root;

    // Resolve the format from the global --format option.
    final format = (globalResults?['format'] as String?) ?? 'human';

    // Load project config (loam.yaml) — missing file returns defaults.
    final config = await _loadConfig(projectRoot);

    // Resolve reporter — FormatNotImplementedError surfaces as a usage error.
    final Reporter reporter;
    try {
      reporter = reporterFor(format);
    } on FormatNotImplementedError catch (e) {
      stderr.writeln(e.toString());
      return 64; // EX_USAGE
    }

    // Progress setup — shared seam (LoamCommand.resolveProgress).
    final progressSink = resolveProgress().sink;

    // Run with accessibility-category filter only.
    // categoryFilter restricts instantiation to accessibility rules (none yet),
    // so the result is trivially empty — Exit 0.
    final outcome = await AnalysisRunner(
      config: config,
      categoryFilter: RuleCategory.accessibility,
      progressSink: progressSink,
      analyzerCacheDirectory: _analyzerCacheFor(projectRoot, config),
    ).analyze(projectRoot);

    // Diagnostic line for human-readable output: identifies this as an
    // accessibility-focused scan (analogous to the stack: diagnostic in scan).
    if (format == 'human') {
      stdout.writeln('loam a11y  Accessibility scan');
    }

    final payload = ReportPayload(
      findings: outcome.findings,
      projectRoot: projectRoot,
      rulesetVersion: AnalysisRunner.rulesetVersionForCategory(
        RuleCategory.accessibility,
        config,
      ),
      toolVersion: loamVersion,
      isTty: stdout.hasTerminal,
      maxFindings: maxFindings,
      suppressedCount: outcome.suppressedCount,
      stats: outcome.stats,
      sourceDirs: config.sourceDirs,
      recommendations: const RecommendationEngine().recommend(outcome.findings),
    );

    await _emitReport(
      rendered: reporter.render(payload),
      format: format,
      commandName: name,
      outputOption: outputPath,
      noOpen: noOpen,
    );

    return outcome.findings.isNotEmpty ? 1 : 0;
  }
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
          'Overrides the positional [path] argument when both are given. '
          'Defaults to the current working directory.',
      defaultsTo: null,
    );
  }

  @override
  final String name = 'init';
  @override
  String get invocation => 'loam init [path] [options]';
  @override
  final String description =
      'Scaffold a loam.yaml configuration file in the current project, '
      'including the architecture layers and boundaries detected from lib/.\n\n'
      '[path] — optional positional path to the project root '
      '(defaults to the current directory). '
      '-p/--project-root overrides [path] when both are given.';

  @override
  Future<int> run() async {
    // Resolve project root via shared resolver (positional or --project-root).
    final rootResult = TargetRootResolver.resolve(argResults);
    if (rootResult is RootUsageError) {
      stderr.writeln(rootResult.message);
      return 64; // EX_USAGE
    }
    final projectRoot = (rootResult as ResolvedRoot).root;
    final target = File(p.join(projectRoot, ConfigLoader.fileName));

    if (target.existsSync()) {
      stderr.writeln(
        'loam init: ${ConfigLoader.fileName} already exists in $projectRoot — '
        'not overwriting. '
        'Edit it manually or delete it first.',
      );
      return 1;
    }

    final architecture = LayerDetector.detect(projectRoot);
    final content = ConfigScaffold.generate(architecture: architecture);
    try {
      // Exclusive create: a config written in the meantime is never replaced.
      target.createSync(exclusive: true);
    } on FileSystemException {
      stderr.writeln(
        'loam init: ${ConfigLoader.fileName} already exists in $projectRoot — '
        'not overwriting.',
      );
      return 1;
    }
    target.writeAsStringSync(content);
    stdout.writeln('loam init: wrote ${ConfigLoader.fileName} to $projectRoot');
    if (!architecture.isEmpty) {
      stdout.writeln(
        'loam init: detected layers (${architecture.layers.keys.join(', ')}) '
        '- written to layers:/boundaries: in ${ConfigLoader.fileName}; '
        'edit or delete them there.',
      );
    }
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
      ..addFlag(
        'prune',
        negatable: false,
        help:
            'Remove stale entries (findings that no longer occur) from '
            'baseline.json without taking in anything new. Always '
            'project-wide.',
      )
      ..addOption(
        'project-root',
        abbr: 'p',
        help:
            'Root directory of the Dart project to analyse. '
            'Overrides the positional [path] argument when both are given. '
            'Defaults to the current working directory.',
        defaultsTo: null,
      );
  }

  @override
  final String name = 'baseline';
  @override
  String get invocation => 'loam baseline [path] [options]';
  @override
  final String description =
      'Show, freeze (--write / --update) or prune (--prune) the baseline for the ratchet gate.\n\n'
      '[path] — optional positional path to the project root '
      '(defaults to the current directory). '
      '-p/--project-root overrides [path] when both are given.';

  @override
  Future<int> run() async {
    final write = argResults?.flag('write') ?? false;
    final update = argResults?.flag('update') ?? false;
    final prune = argResults?.flag('prune') ?? false;
    if (prune && (write || update)) {
      stderr.writeln(
        'loam baseline: --prune cannot be combined with --write or --update.',
      );
      return 64; // EX_USAGE
    }

    // Resolve project root via shared resolver (positional or --project-root).
    final rootResult = TargetRootResolver.resolve(argResults);
    if (rootResult is RootUsageError) {
      stderr.writeln(rootResult.message);
      return 64; // EX_USAGE
    }
    final projectRoot = (rootResult as ResolvedRoot).root;

    final engine = BaselineEngine(projectRoot: projectRoot);

    // Load project config (loam.yaml) — missing file returns defaults.
    final config = await _loadConfig(projectRoot);

    // Progress setup — shared seam (LoamCommand.resolveProgress). Only the
    // --write/--update paths run an analysis; the show path reads baseline.json
    // straight from disk and needs no progress sink.
    final progressSink = resolveProgress().sink;

    if (prune) {
      return _runPrune(engine, projectRoot, config, progressSink);
    } else if (write) {
      return _runWrite(engine, projectRoot, config, progressSink);
    } else if (update) {
      return _runUpdate(engine, projectRoot, config, progressSink);
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
    ProgressSink progressSink,
  ) async {
    if (engine.exists) {
      stderr.writeln(
        'Warning: baseline.json already exists in $projectRoot. '
        'Use `loam baseline --update` to refresh it '
        '(--write would overwrite your curated baseline).',
      );
    }
    final findings = await AnalysisRunner(
      config: config,
      progressSink: progressSink,
      analyzerCacheDirectory: _analyzerCacheFor(projectRoot, config),
    ).run(projectRoot);
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
    ProgressSink progressSink,
  ) async {
    if (!engine.exists) {
      stderr.writeln(
        'Warning: no baseline.json found in $projectRoot. '
        'Use `loam baseline --write` to create one.',
      );
    }
    final findings = await AnalysisRunner(
      config: config,
      progressSink: progressSink,
      analyzerCacheDirectory: _analyzerCacheFor(projectRoot, config),
    ).run(projectRoot);
    final version = AnalysisRunner.rulesetVersionForConfig(config);
    engine.write(findings, version);
    final count = findings.length;
    stdout.writeln(
      'loam baseline: updated to $count finding${count == 1 ? '' : 's'} '
      'in baseline.json ($version).',
    );
    return 0;
  }

  /// Removes baseline entries that no longer occur. Never adds anything; the
  /// ruleset version in the file stays as it was.
  Future<int> _runPrune(
    BaselineEngine engine,
    String projectRoot,
    LoamConfig config,
    ProgressSink progressSink,
  ) async {
    final Baseline baseline;
    try {
      baseline = engine.read();
    } on BaselineException catch (e) {
      stderr.writeln('loam baseline: ${e.message}');
      return 66; // EX_NOINPUT, as in `loam gate`.
    }
    final findings = await AnalysisRunner(
      config: config,
      progressSink: progressSink,
    ).run(projectRoot);
    final diff = engine.diff(findings, baseline);
    final removed = engine.prune(baseline, diff.fixedFindings);
    if (removed == 0) {
      stdout.writeln(
        'loam baseline: no stale entries — baseline.json unchanged.',
      );
      return 0;
    }
    final perRule = diff.staleByRule.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
    final left = baseline.findings.length - removed;
    stdout.writeln(
      'loam baseline: pruned $removed stale '
      'entr${removed == 1 ? 'y' : 'ies'} ($perRule); '
      '$left remain in baseline.json.',
    );
    return 0;
  }

  Future<int> _runShow(
    BaselineEngine engine,
    String projectRoot,
    Reporter reporter,
  ) async {
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
        maxFindings: maxFindings,
        recommendations: const RecommendationEngine().recommend(mappedFindings),
      );

      // Emit baseline header so the user knows this is the frozen state.
      final count = baseline.findings.length;
      _noteSink(format).writeln(
        'loam baseline: $count finding${count == 1 ? '' : 's'} '
        '(${baseline.rulesetVersion}, schemaVersion=${baseline.schemaVersion})',
      );

      // Render the frozen findings via the reporter (same rendering path as scan).
      await _emitReport(
        rendered: reporter.render(payload),
        format: format,
        commandName: name,
        outputOption: outputPath,
        noOpen: noOpen,
      );
    } on BaselineException catch (e) {
      stderr.writeln('loam baseline: ${e.message}');
      return 1;
    }
    return 0;
  }
}

// ---------------------------------------------------------------------------
// Shared helper: emit a rendered report.
//
// Streaming formats (human/sarif/json/markdown) go to stdout unchanged. HTML
// is a self-contained document meant to be viewed, so it is written to a file
// (default loam-report.html, override via --output) and — when run
// interactively — opened in the default browser. A non-HTML format also writes
// to a file when --output is given.
//
// The reporter stays a pure renderer (ADR 0001 / reporter.dart); all I/O
// lives here in the CLI layer.
// ---------------------------------------------------------------------------

/// Resolves `--staged` / `--since` / `--changed` for [projectRoot].
///
/// `files` is `null` when no flag was given (whole project); `error` carries
/// the message for exit 64 (no repository, unknown ref, conflicting flags).
Future<({Set<String>? files, String? error})> _resolveChangedScope(
  ArgResults? results,
  String projectRoot,
) async {
  try {
    final selection = changedSelectionFrom(results);
    if (selection == null) return (files: null, error: null);
    final files = await const ChangedFilesResolver().resolve(
      p.normalize(p.absolute(projectRoot)),
      selection,
    );
    return (files: files, error: null);
  } on ChangedFilesException catch (e) {
    return (files: null, error: 'loam: $e');
  }
}

String _changedScopeNote(String command, int fileCount) =>
    'loam $command: analysis is project-wide; reporting only the '
    '$fileCount changed file${fileCount == 1 ? '' : 's'}.';

/// Formats whose stdout is one parseable document (JSON, SARIF). Free text
/// next to it would break the parse, so notes go to stderr (see [_noteSink]).
bool _isDocumentFormat(String format) => format == 'json' || format == 'sarif';

/// Where summary lines and hints go: stdout for the human/HTML runs, stderr
/// for every other format so stdout carries nothing but the report.
IOSink _noteSink(String format) =>
    format == 'human' || format == 'html' ? stdout : stderr;

Future<void> _emitReport({
  required String rendered,
  required String format,
  required String commandName,
  required String? outputOption,
  required bool noOpen,
}) async {
  final isHtml = format == 'html';
  // Target file: HTML always writes a file; other formats only with --output.
  final targetPath =
      outputOption ?? (isHtml ? defaultHtmlReportFileName : null);

  if (targetPath == null) {
    stdout.write(rendered);
    return;
  }

  final file = File(targetPath)..writeAsStringSync(rendered);
  final absPath = p.absolute(file.path);

  var opened = false;
  if (isHtml &&
      shouldOpenBrowser(
        isTty: stdout.hasTerminal,
        noOpenFlag: noOpen,
        environment: Platform.environment,
      )) {
    opened = await _openInBrowser(absPath);
  }

  stdout.writeln(
    'loam $commandName: ${isHtml ? 'HTML-Report' : 'Report'} → $absPath'
    '${opened ? ' (im Browser geöffnet)' : ''}',
  );
}

/// Best-effort: opens [absPath] in the default browser. Returns whether the
/// launch was attempted successfully. Never throws — failing to open a browser
/// must not change the command's exit code (the file is already written).
Future<bool> _openInBrowser(String absPath) async {
  final command = browserOpenCommand(
    absPath,
    operatingSystem: Platform.operatingSystem,
  );
  if (command == null) return false;
  try {
    final result = await Process.run(command.first, command.sublist(1));
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Shared helper: format the stack: … diagnostic line from a [StackProfile].
//
// Human-only output — printed before the findings report in `loam scan`.
// Structured formats (json/sarif/html/markdown) suppress this line because
// extra text would break their parseable output.
// ---------------------------------------------------------------------------

String _formatStackDiagnostic(StackProfile profile) {
  final parts = <String>[];
  if (profile.isFlutter) parts.add('flutter');
  if (profile.detectedGenerators.isNotEmpty) {
    final gens = (profile.detectedGenerators.toList()..sort()).join(', ');
    parts.add(gens);
  }
  if (parts.isEmpty) return 'stack: dart';
  return 'stack: ${parts.join(' · ')}';
}

// ---------------------------------------------------------------------------
// Shared helper: load loam.yaml config for the given project root.
//
// Missing file → LoamConfig.defaults() (Zero-Config is the Normalfall).
// Syntax error or unknown ruleId → propagates ConfigLoadException so
// commands can surface a clear message without a raw stacktrace.
// ---------------------------------------------------------------------------

Future<LoamConfig> _loadConfig(String projectRoot) async {
  final config = await ConfigLoader.load(
    projectRoot,
    knownRuleIds: AnalysisRunner.fullRegistryIds.toSet(),
  );
  _lastLoadedConfig ??= config;
  return config;
}

/// Set from the global `--no-cache` flag at the start of every [run].
bool _noCacheFlag = false;

/// Where the analyzer keeps its summary store for [projectRoot]
/// (`.dart_tool/loam/analyzer/`), or `null` when caching is off for this run
/// (`--no-cache`) or for the project (`cache: false`).
String? _analyzerCacheFor(String projectRoot, LoamConfig config) =>
    _noCacheFlag || !config.cache
    ? null
    : p.join(
        p.normalize(p.absolute(projectRoot)),
        '.dart_tool',
        'loam',
        'analyzer',
      );

/// The first config a command loaded in this run (the analysed project's), so
/// the update decision honours that project's pin. `null` until loaded.
LoamConfig? _lastLoadedConfig;

// ---------------------------------------------------------------------------
// Health-command terminal renderer.
//
// Renders Score + Grade + descending-sorted Hotspot table to [sink].
// This renderer is ONLY used by _HealthCommand — it deliberately does NOT
// route through Reporter/ReportPayload/Finding.
// ---------------------------------------------------------------------------

/// Renders [report] to [sink] in a human-readable terminal format.
///
/// Output:
/// ```
/// loam health  Health-Score: 87 / 100  Grade: B
///   Findings:   92 / 100
///   Complexity: 80 / 100
///
/// Hotspots (cyclomatic/cognitive complexity — top N, descending):
///
///   FILE:LINE                          SYMBOL                     CYC  COG
///   lib/src/example.dart:42            MyClass.compute             21    8
///   ...
///
/// (N hotspots)
/// ```
///
/// When the hotspot list is empty, shows a "No hotspots detected." line
/// instead of the table.
void _renderHealthReport(
  HealthReport report,
  String projectRoot,
  StringSink sink,
) {
  sink.writeln(
    'loam health  '
    'Health-Score: ${report.score} / 100  '
    'Grade: ${report.grade}',
  );
  sink.writeln(
    '  Findings:   ${report.findingsContribution} / 100\n'
    '  Complexity: ${report.complexityContribution} / 100',
  );

  final hotspots = report.hotspots;

  if (hotspots.isEmpty) {
    sink.writeln();
    sink.writeln('No hotspots detected.');
    return;
  }

  sink.writeln();
  sink.writeln(
    'Hotspots (cyclomatic/cognitive complexity — '
    'top ${hotspots.length}, descending):',
  );
  sink.writeln();

  // Column widths: FILE:LINE = 38, SYMBOL = 30, CYC = 5, COG = 5.
  // These are minimum widths; values that exceed them push right naturally.
  const fileColW = 38;
  const symColW = 30;

  sink.writeln(
    '${'FILE:LINE'.padRight(fileColW)}  '
    '${'SYMBOL'.padRight(symColW)}  '
    '${'CYC'.padLeft(5)}  '
    '${'COG'.padLeft(5)}',
  );

  for (final h in hotspots) {
    final fileRef = '${h.filePath}:${h.line}';
    sink.writeln(
      '${fileRef.padRight(fileColW)}  '
      '${h.qualifiedName.padRight(symColW)}  '
      '${h.metrics.cyclomatic.toString().padLeft(5)}  '
      '${h.metrics.cognitive.toString().padLeft(5)}',
    );
  }

  sink.writeln();
  final n = hotspots.length;
  sink.writeln('($n hotspot${n == 1 ? '' : 's'})');
}
