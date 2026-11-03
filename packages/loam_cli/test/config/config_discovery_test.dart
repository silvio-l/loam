@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/config_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../support/shared_store.dart';

/// Discovery + layering behaviour of [ConfigLoader.load].
///
/// loam walks up from the analysed project root to (and including) the
/// enclosing git repository root, layering every `loam.yaml` it finds
/// farthest→nearest (nearer overrides). The walk is bounded at the git root so
/// discovery is repo-relative and reproducible — a config above the repo (e.g.
/// in `$HOME`) is never picked up.
void main() {
  useSharedAnalyzerStore();

  late Directory repo;

  /// Creates `<repo>/.git` so [repo] is recognised as the discovery boundary.
  void markGitRoot(Directory dir) {
    Directory(p.join(dir.path, '.git')).createSync();
  }

  void writeYaml(Directory dir, String body) {
    dir.createSync(recursive: true);
    File(p.join(dir.path, 'loam.yaml')).writeAsStringSync(body);
  }

  setUp(() {
    repo = Directory.systemTemp.createTempSync('loam_discovery_');
    markGitRoot(repo);
  });

  tearDown(() => repo.deleteSync(recursive: true));

  // ---------------------------------------------------------------------------
  // Discovery: a repo-root loam.yaml is honoured when analysing a sub-package.
  // ---------------------------------------------------------------------------
  test('repo-root loam.yaml applies when analysing a nested project', () async {
    writeYaml(repo, 'a11y: false\nignore:\n  - "build/**"\n');
    final pkg = Directory(p.join(repo.path, 'packages', 'cli'))
      ..createSync(recursive: true);

    final config = await ConfigLoader.load(pkg.path);

    expect(config.includeA11y, isFalse, reason: 'inherited from repo root');
    expect(config.ignoreGlobs, contains('build/**'));
  });

  // ---------------------------------------------------------------------------
  // Layering: root provides the base, nearer overrides / extends it.
  // ---------------------------------------------------------------------------
  test('nested loam.yaml layers over the repo-root one', () async {
    writeYaml(
      repo,
      'a11y: false\n'
      'update_check: false\n'
      'ignore:\n  - "build/**"\n'
      'rules:\n  code-duplicates: false\n',
    );
    final pkg = Directory(p.join(repo.path, 'packages', 'cli'));
    writeYaml(
      pkg,
      'ignore:\n  - "test/**"\n'
      'rules:\n  complexity-hotspots: false\n',
    );

    final config = await ConfigLoader.load(
      pkg.path,
      knownRuleIds: {'code-duplicates', 'complexity-hotspots'},
    );

    // ignore: additive (root first, then nearer), de-duplicated, order kept.
    expect(config.ignoreGlobs, ['build/**', 'test/**']);
    // rules: merged per ruleId across layers.
    expect(
      config.isRuleDisabled('code-duplicates'),
      isTrue,
      reason: 'inherited from root',
    );
    expect(
      config.isRuleDisabled('complexity-hotspots'),
      isTrue,
      reason: 'set in nested',
    );
    // scalar: inherited from root when the nearer layer is silent.
    expect(config.updateCheck, isFalse);
    expect(config.includeA11y, isFalse);
  });

  test(
    'intended-pattern lists are united, boilerplate flag is overridden',
    () async {
      writeYaml(
        repo,
        'code_duplicates:\n'
        '  boilerplate: false\n'
        '  boilerplate_methods: [build, toXml]\n'
        'unused_public_exports:\n'
        '  annotations: [Keep, Api]\n',
      );
      final pkg = Directory(p.join(repo.path, 'app'));
      writeYaml(
        pkg,
        'code_duplicates:\n'
        '  boilerplate: true\n'
        '  boilerplate_methods: [toXml, render]\n'
        'unused_public_exports:\n'
        '  annotations: [Api, Other]\n',
      );

      final config = await ConfigLoader.load(pkg.path);

      expect(config.boilerplateMethods, ['build', 'toXml', 'render']);
      expect(config.reservedAnnotations, ['Keep', 'Api', 'Other']);
      expect(config.skipBoilerplate, isTrue, reason: 'nearer layer wins');
    },
  );

  // ---------------------------------------------------------------------------
  // Override precedence: the nearer scalar wins over the farther one.
  // ---------------------------------------------------------------------------
  test('nearer scalar overrides the farther one', () async {
    writeYaml(repo, 'a11y: false\nsource_dirs:\n  - lib\n');
    final pkg = Directory(p.join(repo.path, 'app'));
    writeYaml(pkg, 'a11y: true\nsource_dirs:\n  - lib\n  - bin\n');

    final config = await ConfigLoader.load(pkg.path);

    expect(config.includeA11y, isTrue, reason: 'nearer wins');
    expect(config.sourceDirs, ['lib', 'bin'], reason: 'nearer list replaces');
  });

  // ---------------------------------------------------------------------------
  // source_dirs inherits when the nearer layer does not specify it.
  // ---------------------------------------------------------------------------
  test('source_dirs is inherited when the nearer layer omits it', () async {
    writeYaml(repo, 'source_dirs:\n  - lib\n  - tool\n');
    final pkg = Directory(p.join(repo.path, 'app'));
    writeYaml(pkg, 'a11y: false\n');

    final config = await ConfigLoader.load(pkg.path);

    expect(config.sourceDirs, ['lib', 'tool']);
  });

  // ---------------------------------------------------------------------------
  // Boundary: a loam.yaml ABOVE the git root must never be picked up.
  // ---------------------------------------------------------------------------
  test('config above the git root is not discovered', () async {
    // repo is the git root; place a loam.yaml in its PARENT (outside the repo).
    final outside = repo.parent;
    final strayPath = p.join(outside.path, 'loam.yaml');
    final stray = File(strayPath);
    final hadStray = stray.existsSync();
    if (!hadStray) stray.writeAsStringSync('a11y: false\n');
    addTearDown(() {
      if (!hadStray && stray.existsSync()) stray.deleteSync();
    });

    final pkg = Directory(p.join(repo.path, 'app'));
    pkg.createSync(recursive: true);

    final config = await ConfigLoader.load(pkg.path);

    // No loam.yaml inside the repo → defaults; the stray parent one is ignored.
    expect(config.includeA11y, isTrue);
  });

  // ---------------------------------------------------------------------------
  // No git root → only <projectRoot>/loam.yaml is considered (no upward walk).
  // ---------------------------------------------------------------------------
  test('without a git root only the project-root config is read', () async {
    final nogit = Directory.systemTemp.createTempSync('loam_nogit_');
    addTearDown(() => nogit.deleteSync(recursive: true));
    // Parent config that must NOT be read (no .git anywhere → no walk).
    writeYaml(nogit, 'a11y: false\n');
    final pkg = Directory(p.join(nogit.path, 'app'));
    pkg.createSync(recursive: true);

    final config = await ConfigLoader.load(pkg.path);

    expect(
      config.includeA11y,
      isTrue,
      reason: 'parent not walked without .git',
    );
  });

  // ---------------------------------------------------------------------------
  // required_version / auto_update: scalar override, omitted -> inherited.
  // ---------------------------------------------------------------------------
  test('required_version and auto_update inherit over two levels', () async {
    writeYaml(repo, 'required_version: "1.2.3"\nauto_update: false\n');
    final mid = Directory(p.join(repo.path, 'packages'));
    writeYaml(mid, 'a11y: false\n'); // omits both: inherited
    final pkg = Directory(p.join(mid.path, 'cli'))..createSync();

    final inherited = await ConfigLoader.load(pkg.path);
    expect(inherited.requiredVersion.toString(), '1.2.3');
    expect(inherited.autoUpdate, isFalse);

    writeYaml(pkg, 'required_version: "2.0.0"\nauto_update: true\n');
    final overridden = await ConfigLoader.load(pkg.path);
    expect(overridden.requiredVersion.toString(), '2.0.0');
    expect(overridden.autoUpdate, isTrue);
  });

  // ---------------------------------------------------------------------------
  // A malformed file anywhere in the chain still raises ConfigLoadException.
  // ---------------------------------------------------------------------------
  test('malformed config in any layer raises ConfigLoadException', () async {
    writeYaml(repo, 'a11y: [this is not a bool]\n');
    final pkg = Directory(p.join(repo.path, 'app'));
    pkg.createSync(recursive: true);

    expect(
      () => ConfigLoader.load(pkg.path),
      throwsA(isA<ConfigLoadException>()),
    );
  });
}
