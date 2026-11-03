import 'package:args/args.dart';
import 'package:loam/src/baseline/baseline.dart';
import 'package:loam/src/baseline/baseline_diff.dart';
import 'package:loam/src/changed/changed_files.dart';
import 'package:loam/src/model/finding.dart';
import 'package:test/test.dart';

Finding _f(String path, String fp) => Finding(
  ruleId: 'r',
  severity: Severity.warning,
  filePath: path,
  line: 1,
  message: 'm',
  fingerprint: fp,
);

BaselineFinding _b(String path, String fp) => BaselineFinding(
  fingerprint: fp,
  ruleId: 'r',
  filePath: path,
  line: 1,
  message: 'm',
);

/// A scripted [GitRunner]: answers by the joined argument list and records
/// every call.
class _FakeGit {
  _FakeGit(this.answers);
  final Map<String, GitOutput> answers;
  final calls = <String>[];

  Future<GitOutput> call(List<String> args, String cwd) async {
    // A trailing `--` (path separator guard) is not part of what is scripted.
    final key = (args.last == '--' ? args.sublist(0, args.length - 1) : args)
        .join(' ');
    calls.add(key);
    return answers[key] ??
        (exitCode: 1, stdout: '', stderr: 'unscripted: $key');
  }
}

GitOutput _ok(String out) => (exitCode: 0, stdout: out, stderr: '');
GitOutput _fail([String err = 'fatal']) =>
    (exitCode: 1, stdout: '', stderr: err);

const _inside = {
  'rev-parse --is-inside-work-tree': (
    exitCode: 0,
    stdout: 'true\n',
    stderr: '',
  ),
};
const _diff = 'diff --relative --name-only -z --diff-filter=d';

void main() {
  group('changedSelectionFrom', () {
    ArgResults parse(List<String> args) {
      final parser = ArgParser();
      addChangedOptions(parser);
      return parser.parse(args);
    }

    test('no flag selects the whole project', () {
      expect(changedSelectionFrom(parse([])), isNull);
    });

    test('each flag maps to its selection', () {
      expect(changedSelectionFrom(parse(['--staged'])), isA<StagedSelection>());
      expect(
        changedSelectionFrom(parse(['--changed'])),
        isA<WorkingCopySelection>(),
      );
      final since = changedSelectionFrom(parse(['--since', 'main']));
      expect((since! as SinceSelection).ref, 'main');
    });

    test('a --since value that looks like an option is rejected', () {
      expect(
        () => changedSelectionFrom(parse(['--since=--output=x'])),
        throwsA(isA<ChangedFilesException>()),
      );
    });

    test('combining flags is rejected', () {
      expect(
        () => changedSelectionFrom(parse(['--staged', '--changed'])),
        throwsA(isA<ChangedFilesException>()),
      );
      expect(
        () => changedSelectionFrom(parse(['--staged', '--since', 'main'])),
        throwsA(isA<ChangedFilesException>()),
      );
    });
  });

  group('ChangedFilesResolver', () {
    test('outside a repository fails with a clear message', () {
      final git = _FakeGit({
        'rev-parse --is-inside-work-tree': _fail('not a git repository'),
      });
      expect(
        ChangedFilesResolver(
          git: git.call,
        ).resolve('/p', const StagedSelection()),
        throwsA(
          isA<ChangedFilesException>().having(
            (e) => e.message,
            'message',
            contains('Not a git repository'),
          ),
        ),
      );
    });

    test('staged lists the index diff, NUL-separated, POSIX', () async {
      final git = _FakeGit({
        ..._inside,
        '$_diff --cached': _ok('lib/a.dart\u0000lib/src/b c.dart\u0000'),
      });
      final files = await ChangedFilesResolver(
        git: git.call,
      ).resolve('/p', const StagedSelection());
      expect(files, {'lib/a.dart', 'lib/src/b c.dart'});
    });

    test('since diffs from the merge base, not the ref tip', () async {
      final git = _FakeGit({
        ..._inside,
        'rev-parse --verify -q main^{commit}': _ok('abc\n'),
        'merge-base main HEAD': _ok('base123\n'),
        '$_diff base123': _ok('lib/x.dart\u0000'),
      });
      final files = await ChangedFilesResolver(
        git: git.call,
      ).resolve('/p', const SinceSelection('main'));
      expect(files, {'lib/x.dart'});
    });

    test('since falls back to the ref without a common ancestor', () async {
      final git = _FakeGit({
        ..._inside,
        'rev-parse --verify -q other^{commit}': _ok('abc\n'),
        'merge-base other HEAD': _fail(),
        '$_diff other': _ok('lib/y.dart\u0000'),
      });
      final files = await ChangedFilesResolver(
        git: git.call,
      ).resolve('/p', const SinceSelection('other'));
      expect(files, {'lib/y.dart'});
    });

    test('since with an unknown ref names the ref', () {
      final git = _FakeGit({
        ..._inside,
        'rev-parse --verify -q nope^{commit}': _fail(),
      });
      expect(
        ChangedFilesResolver(
          git: git.call,
        ).resolve('/p', const SinceSelection('nope')),
        throwsA(
          isA<ChangedFilesException>().having(
            (e) => e.message,
            'message',
            contains('"nope"'),
          ),
        ),
      );
    });

    test('since with an option-like ref never reaches git', () async {
      final git = _FakeGit({..._inside});
      await expectLater(
        ChangedFilesResolver(
          git: git.call,
        ).resolve('/p', const SinceSelection('--output=x')),
        throwsA(isA<ChangedFilesException>()),
      );
      expect(git.calls.where((c) => c.contains('--output')), isEmpty);
    });

    test('changed merges tracked diff and untracked files', () async {
      final git = _FakeGit({
        ..._inside,
        'rev-parse --verify -q HEAD': _ok('abc\n'),
        '$_diff HEAD': _ok('lib/a.dart\u0000'),
        'ls-files -z --others --exclude-standard': _ok('lib/new.dart\u0000'),
      });
      final files = await ChangedFilesResolver(
        git: git.call,
      ).resolve('/p', const WorkingCopySelection());
      expect(files, {'lib/a.dart', 'lib/new.dart'});
    });

    test('changed in a repo without commits counts every file', () async {
      final git = _FakeGit({
        ..._inside,
        'rev-parse --verify -q HEAD': _fail(),
        'ls-files -z --cached --others --exclude-standard': _ok(
          'lib/a.dart\u0000',
        ),
      });
      final files = await ChangedFilesResolver(
        git: git.call,
      ).resolve('/p', const WorkingCopySelection());
      expect(files, {'lib/a.dart'});
    });
  });

  group('scoping', () {
    test('filterFindingsToFiles keeps only findings in the file set', () {
      final out = filterFindingsToFiles(
        [_f('lib/a.dart', '1'), _f('lib/b.dart', '2')],
        {'lib/b.dart'},
      );
      expect(out.map((f) => f.fingerprint), ['2']);
    });

    test('scopeDiffToFiles drops other files, incl. "fixed" baseline rows', () {
      final diff = BaselineDiff(
        newFindings: [_f('lib/a.dart', 'n1'), _f('lib/b.dart', 'n2')],
        keptFindings: [_f('lib/b.dart', 'k1'), _f('lib/c.dart', 'k2')],
        fixedFindings: [_b('lib/a.dart', 'x1'), _b('lib/c.dart', 'x2')],
      );
      final scoped = scopeDiffToFiles(diff, {'lib/a.dart'});
      expect(scoped.newFindings.map((f) => f.fingerprint), ['n1']);
      expect(scoped.keptFindings, isEmpty);
      expect(scoped.fixedFindings.map((f) => f.fingerprint), ['x1']);
    });
  });
}
