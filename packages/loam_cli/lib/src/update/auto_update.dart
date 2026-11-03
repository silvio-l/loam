import 'package:pub_semver/pub_semver.dart';

import 'update_notice.dart';
import 'update_policy.dart';
import 'update_state.dart';

/// Starts the background update worker (injected; the CLI spawns a detached
/// copy of itself, tests record the call).
typedef WorkerSpawner = Future<void> Function(UpdateMode mode);

/// Lines describing how the rule set changed between two versions, or an
/// empty list when nothing changed or the old rule set is unknown.
List<String> describeRulesetChange(
  List<String> previousRuleIds,
  List<String> currentRuleIds,
) {
  if (previousRuleIds.isEmpty) return const [];
  final before = previousRuleIds.toSet();
  final after = currentRuleIds.toSet();
  final added = after.difference(before).toList()..sort();
  final removed = before.difference(after).toList()..sort();
  if (added.isEmpty && removed.isEmpty) return const [];
  return [
    'loam: the ruleset changed with this update'
        '${added.isEmpty ? '' : ' — new rules: ${added.join(', ')}'}'
        '${removed.isEmpty ? '' : ' — removed rules: ${removed.join(', ')}'}.',
    'loam: new findings from these rules are not regressions in your code; '
        'review them, then refresh the baseline with `loam baseline --update`.',
  ];
}

/// The foreground half of the auto-update. It never touches the network and
/// never waits: it prints what the last background run found and starts the
/// next background run when one is due.
class AutoUpdateCoordinator {
  /// Creates a coordinator for the running [current] version.
  AutoUpdateCoordinator({
    required Version current,
    required List<String> currentRuleIds,
    required String upgradeCommand,
    required UpdateStateStore store,
    required WorkerSpawner spawnWorker,
    DateTime Function()? now,
  }) : _current = current,
       _currentRuleIds = currentRuleIds,
       _upgradeCommand = upgradeCommand,
       _store = store,
       _spawn = spawnWorker,
       _now = now ?? (() => DateTime.now().toUtc());

  final Version _current;
  final List<String> _currentRuleIds;
  final String _upgradeCommand;
  final UpdateStateStore _store;
  final WorkerSpawner _spawn;
  final DateTime Function() _now;

  /// Lines about the last background install, printed once and before the
  /// command output: the applied update (with any ruleset change) or the
  /// failure with the manual command. An applied update is reported only by
  /// the version it installed, so the message names the binary that runs.
  List<String> takeAnnouncements() {
    var lines = const <String>[];
    // Decide and mark under the store's write, so two parallel runs never
    // print the same outcome and a newer outcome is never marked by mistake.
    _store.update((state) {
      final outcome = state.outcome;
      if (outcome == null || outcome.reported) return state;
      final announced = _announcement(outcome);
      if (announced.isEmpty) return state;
      lines = announced;
      return state.copyWith(outcome: outcome.markReported());
    });
    return lines;
  }

  List<String> _announcement(UpdateOutcome outcome) {
    switch (outcome.kind) {
      case UpdateOutcomeKind.applied:
        if (outcome.to != _current) return const [];
        return [
          'loam: updated automatically from ${outcome.from} to ${outcome.to}.',
          ...describeRulesetChange(outcome.previousRuleIds, _currentRuleIds),
        ];
      case UpdateOutcomeKind.failed:
        if (!isNewerStable(_current, outcome.to)) return const [];
        return [
          'loam: automatic update to ${outcome.to} failed '
              '(${outcome.reason ?? 'unknown reason'}). '
              'Update manually: $_upgradeCommand',
        ];
    }
  }

  /// Applies [mode] after the command ran and returns the lines to print.
  ///
  /// - [UpdateMode.off]: nothing.
  /// - A check is due (once per [kUpdateCheckInterval]): the timestamp is
  ///   claimed first, so parallel runs start at most one worker, then the
  ///   worker starts in the background.
  /// - [UpdateMode.notify]: a newer version known from an earlier check is
  ///   reported with the upgrade command.
  /// - [UpdateMode.auto]: no notice — the worker installs by itself and the
  ///   next run reports the result via [takeAnnouncements].
  Future<List<String>> afterRun(UpdateMode mode) async {
    if (mode == UpdateMode.off) return const [];
    final now = _now();
    var due = false;
    UpdateState? seen;
    // Claim the check atomically: of parallel runs only one sees it as due.
    // A skipped write (lock busy, no cache dir) leaves [seen] null: no check
    // is claimed, but a known newer version is still reported.
    _store.update((current) {
      seen = current;
      due = isCheckDue(current, now);
      return due ? current.copyWith(checkedAt: now) : current;
    });
    if (due) await _spawn(mode);

    final latest = (seen ?? _store.read()).latest;
    if (mode == UpdateMode.auto) return const [];
    if (latest == null || !isNewerStable(_current, latest)) return const [];
    return [
      formatUpdateNotice(
        UpdateNotice(
          currentVersion: _current,
          latestVersion: latest,
          updateCommand: _upgradeCommand,
        ),
      ),
    ];
  }
}
