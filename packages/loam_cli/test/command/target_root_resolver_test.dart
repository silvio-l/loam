@TestOn('vm')
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:loam/src/command/target_root_resolver.dart';
import 'package:test/test.dart';

/// Minimal [ArgResults] stub that exposes only the fields [TargetRootResolver]
/// reads: `project-root` option and `rest` positionals.
///
/// The real [ArgResults] constructor is not public, so we use a thin wrapper
/// around an [ArgParser] + [ArgParser.parse] call.
ArgResults _parse({String? projectRoot, List<String> positionals = const []}) {
  final parser = ArgParser()
    ..addOption('project-root', abbr: 'p', defaultsTo: null);
  final args = [
    if (projectRoot != null) ...['--project-root', projectRoot],
    ...positionals,
  ];
  return parser.parse(args);
}

void main() {
  group('TargetRootResolver', () {
    // -------------------------------------------------------------------------
    // (a) only --project-root set → its value wins
    // -------------------------------------------------------------------------
    test('(a) only -p set → returns its value', () {
      final result = TargetRootResolver.resolve(
        _parse(projectRoot: '/my/proj'),
      );
      expect(result, isA<ResolvedRoot>());
      expect((result as ResolvedRoot).root, equals('/my/proj'));
    });

    // -------------------------------------------------------------------------
    // (b) only one positional → positional is the root
    // -------------------------------------------------------------------------
    test('(b) only one positional → returns positional path', () {
      final result = TargetRootResolver.resolve(
        _parse(positionals: ['/some/path']),
      );
      expect(result, isA<ResolvedRoot>());
      expect((result as ResolvedRoot).root, equals('/some/path'));
    });

    // -------------------------------------------------------------------------
    // (c) neither -p nor positional → CWD
    // -------------------------------------------------------------------------
    test('(c) no args → returns Directory.current.path', () {
      final result = TargetRootResolver.resolve(_parse());
      expect(result, isA<ResolvedRoot>());
      expect((result as ResolvedRoot).root, equals(Directory.current.path));
    });

    // -------------------------------------------------------------------------
    // (d) -p AND positional → -p wins (no error)
    // -------------------------------------------------------------------------
    test('(d) -p and positional → -p wins', () {
      final result = TargetRootResolver.resolve(
        _parse(projectRoot: '/explicit', positionals: ['/positional']),
      );
      expect(result, isA<ResolvedRoot>());
      expect((result as ResolvedRoot).root, equals('/explicit'));
    });

    // -------------------------------------------------------------------------
    // (e) two or more positionals → usage error
    // -------------------------------------------------------------------------
    test('(e) two positionals → RootUsageError', () {
      final result = TargetRootResolver.resolve(
        _parse(positionals: ['/first', '/second']),
      );
      expect(result, isA<RootUsageError>());
      final err = (result as RootUsageError).message;
      expect(err, contains('Too many arguments'));
    });

    test('(e) three positionals → RootUsageError mentioning count', () {
      final result = TargetRootResolver.resolve(
        _parse(positionals: ['/a', '/b', '/c']),
      );
      expect(result, isA<RootUsageError>());
      expect((result as RootUsageError).message, contains('3'));
    });

    // -------------------------------------------------------------------------
    // null ArgResults → CWD (defensive, used when argResults? is null)
    // -------------------------------------------------------------------------
    test('null ArgResults → returns Directory.current.path', () {
      final result = TargetRootResolver.resolve(null);
      expect(result, isA<ResolvedRoot>());
      expect((result as ResolvedRoot).root, equals(Directory.current.path));
    });
  });
}
