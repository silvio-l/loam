import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../baseline/baseline.dart';
import '../baseline/baseline_diff.dart';
import '../model/finding.dart';

/// The outcome of one git invocation, as seen by [ChangedFilesResolver].
typedef GitOutput = ({int exitCode, String stdout, String stderr});

/// Runs `git <args>` inside [workingDirectory].
///
/// The seam that keeps [ChangedFilesResolver] testable without a repository;
/// production uses [runGit].
typedef GitRunner =
    Future<GitOutput> Function(List<String> args, String workingDirectory);

/// The production [GitRunner]: a real `git` process.
///
/// A missing `git` binary is reported as exit code 127 so the caller can
/// surface it as a usage error rather than a crash.
Future<GitOutput> runGit(
  List<String> args,
  String workingDirectory, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  try {
    final proc = await Process.start(
      'git',
      args,
      workingDirectory: workingDirectory,
    );
    final out = proc.stdout.transform(utf8.decoder).join();
    final err = proc.stderr.transform(utf8.decoder).join();
    final code = await proc.exitCode.timeout(
      timeout,
      onTimeout: () {
        proc.kill();
        return 124;
      },
    );
    return (exitCode: code, stdout: await out, stderr: await err);
  } on ProcessException catch (e) {
    return (exitCode: 127, stdout: '', stderr: e.message);
  }
}

/// Which files count as "changed".
sealed class ChangedSelection {
  const ChangedSelection();
}

/// `--staged`: files in the git index that differ from HEAD.
class StagedSelection extends ChangedSelection {
  /// Creates a [StagedSelection].
  const StagedSelection();
}

/// `--since <ref>`: files that differ between the merge base of [ref] and
/// HEAD, and the working tree.
class SinceSelection extends ChangedSelection {
  /// Creates a [SinceSelection] for [ref].
  const SinceSelection(this.ref);

  /// The git ref (branch, tag, commit) to compare against.
  final String ref;
}

/// `--changed`: files that differ from HEAD in the working copy (staged,
/// unstaged) plus untracked files that are not ignored.
class WorkingCopySelection extends ChangedSelection {
  /// Creates a [WorkingCopySelection].
  const WorkingCopySelection();
}

/// Thrown when the changed-file set cannot be determined (no repository,
/// unknown ref, git missing). The message is shown to the user as-is; the CLI
/// maps it to exit 64.
class ChangedFilesException implements Exception {
  /// Creates a [ChangedFilesException].
  const ChangedFilesException(this.message);

  /// Human-readable cause.
  final String message;

  @override
  String toString() => message;
}

/// Registers `--staged`, `--since` and `--changed` on [parser].
void addChangedOptions(ArgParser parser) {
  parser
    ..addFlag(
      'staged',
      negatable: false,
      help:
          'Report only findings in files staged in git (pre-commit use). '
          'The analysis itself stays project-wide.',
    )
    ..addOption(
      'since',
      valueHelp: 'ref',
      help:
          'Report only findings in files changed since <ref> (branch, tag or '
          'commit; compared from the merge base with HEAD, including the '
          'working copy).',
    )
    ..addFlag(
      'changed',
      negatable: false,
      help:
          'Report only findings in files changed in the working copy '
          '(staged, unstaged and untracked).',
    );
}

/// Reads the selection from [results], or `null` when none of the flags is
/// set. Throws [ChangedFilesException] when more than one is given.
ChangedSelection? changedSelectionFrom(ArgResults? results) {
  if (results == null) return null;
  final staged = results.flag('staged');
  final since = results.option('since');
  final changed = results.flag('changed');
  final given = [staged, since != null, changed].where((v) => v).length;
  if (given > 1) {
    throw const ChangedFilesException(
      'Use only one of --staged, --since <ref> and --changed.',
    );
  }
  if (staged) return const StagedSelection();
  if (since != null) {
    if (since.trim().isEmpty) {
      throw const ChangedFilesException('--since needs a git ref.');
    }
    if (since.startsWith('-')) {
      // A ref can never start with '-'; refuse it so it cannot be read by git
      // as an option (e.g. --since=--output=x).
      throw ChangedFilesException('Invalid git ref for --since: "$since".');
    }
    return SinceSelection(since);
  }
  if (changed) return const WorkingCopySelection();
  return null;
}

/// Resolves a [ChangedSelection] to project-relative POSIX file paths — the
/// format of [Finding.filePath].
class ChangedFilesResolver {
  /// Creates a resolver; [git] defaults to the real `git`.
  const ChangedFilesResolver({this.git = runGit});

  /// The git seam.
  final GitRunner git;

  /// The changed files under [projectRoot] (deleted files excluded).
  ///
  /// `--relative` makes git print paths relative to [projectRoot] and drop
  /// files outside it, so a project in a repo subdirectory still matches
  /// finding paths. Throws [ChangedFilesException] outside a repository or for
  /// an unknown ref.
  Future<Set<String>> resolve(
    String projectRoot,
    ChangedSelection selection,
  ) async {
    final inside = await git([
      'rev-parse',
      '--is-inside-work-tree',
    ], projectRoot);
    if (inside.exitCode == 124) {
      throw const ChangedFilesException('git timed out.');
    }
    if (inside.exitCode == 127) {
      throw ChangedFilesException(
        'git is not available: ${inside.stderr.trim()}',
      );
    }
    if (inside.exitCode != 0 || inside.stdout.trim() != 'true') {
      throw ChangedFilesException(
        'Not a git repository: $projectRoot. '
        '--staged, --since and --changed need git.',
      );
    }

    const diff = ['diff', '--relative', '--name-only', '-z', '--diff-filter=d'];
    switch (selection) {
      case StagedSelection():
        return _paths(await git([...diff, '--cached'], projectRoot));
      case SinceSelection(:final ref):
        final base = await _mergeBase(ref, projectRoot);
        return _paths(await git([...diff, base], projectRoot));
      case WorkingCopySelection():
        final hasHead = await git([
          'rev-parse',
          '--verify',
          '-q',
          'HEAD',
        ], projectRoot);
        if (hasHead.exitCode != 0) {
          // No commit yet: everything tracked or untracked counts as changed.
          return _paths(
            await git([
              'ls-files',
              '-z',
              '--cached',
              '--others',
              '--exclude-standard',
            ], projectRoot),
          );
        }
        final tracked = _paths(await git([...diff, 'HEAD'], projectRoot));
        final untracked = _paths(
          await git([
            'ls-files',
            '-z',
            '--others',
            '--exclude-standard',
          ], projectRoot),
        );
        return {...tracked, ...untracked};
    }
  }

  Future<String> _mergeBase(String ref, String cwd) async {
    if (ref.startsWith('-')) {
      throw ChangedFilesException('Invalid git ref for --since: "$ref".');
    }
    final verify = await git([
      'rev-parse',
      '--verify',
      '-q',
      '$ref^{commit}',
    ], cwd);
    if (verify.exitCode != 0) {
      throw ChangedFilesException(
        'Unknown git ref for --since: "$ref". '
        'Use a branch, tag or commit that exists in this repository.',
      );
    }
    final mb = await git(['merge-base', ref, 'HEAD'], cwd);
    final sha = mb.stdout.trim();
    // No common ancestor (or no HEAD yet): compare against the ref itself.
    return mb.exitCode == 0 && sha.isNotEmpty ? sha : ref;
  }

  Set<String> _paths(GitOutput out) {
    if (out.exitCode != 0) {
      throw ChangedFilesException('git failed: ${out.stderr.trim()}');
    }
    return out.stdout.split('\u0000').where((s) => s.isNotEmpty).toSet();
  }
}

/// Keeps only the [findings] located in [files].
List<Finding> filterFindingsToFiles(
  List<Finding> findings,
  Set<String> files,
) => [
  for (final f in findings)
    if (files.contains(f.filePath)) f,
];

/// Restricts a ratchet [BaselineDiff] to [files].
///
/// The diff must be computed from the full, project-wide findings first:
/// filtering before diffing would report every baseline entry outside [files]
/// as "fixed". Scoping afterwards keeps new/kept/fixed counts about the
/// selected files only, so the gate can fail solely on new findings there.
BaselineDiff scopeDiffToFiles(BaselineDiff diff, Set<String> files) {
  return BaselineDiff(
    newFindings: filterFindingsToFiles(diff.newFindings, files),
    keptFindings: filterFindingsToFiles(diff.keptFindings, files),
    fixedFindings: [
      for (final BaselineFinding f in diff.fixedFindings)
        if (files.contains(f.filePath)) f,
    ],
  );
}
