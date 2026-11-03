@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/anchor.dart';
import 'package:loam/src/rules/a11y_form_field_label_rule.dart';
import 'package:loam/src/rules/a11y_icon_button_label_rule.dart';
import 'package:loam/src/rules/a11y_image_label_rule.dart';
import 'package:loam/src/rules/a11y_interactive_semantics_rule.dart';
import 'package:loam/src/rules/rule.dart';
import 'package:loam/src/rules/slop_empty_catch_rule.dart';
import 'package:loam/src/rules/slop_unjustified_ignore_rule.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../support/shared_store.dart';

/// Issue #3: fingerprints derive from scope and content, never from running
/// numbers, so code inserted before a finding must not change its fingerprint.
void main() {
  useSharedAnalyzerStore();

  late Directory tmp;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('loam_fp_stability_');
    File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync(
      'name: fp_fixture\npublish_to: none\n'
      'environment:\n  sdk: ^3.11.0\n'
      'dependencies:\n  flutter:\n    path: '
      '${p.join(Directory.current.path, 'test', 'fixtures', 'flutter_stub')}\n',
    );
    Directory(p.join(tmp.path, 'lib')).createSync();
    final r = await Process.run('dart', [
      'pub',
      'get',
    ], workingDirectory: tmp.path);
    if (r.exitCode != 0) fail('dart pub get failed: ${r.stderr}');
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<List<String>> fingerprints(
    String source,
    String ruleId, {
    required List<String> Function(ProjectLoadResult) run,
  }) async {
    File(p.join(tmp.path, 'lib', 'a.dart')).writeAsStringSync(source);
    return run(await const ProjectLoader().load(tmp.path));
  }

  Future<List<String>> catchPrints(String source) => fingerprints(
    source,
    'slop-empty-catch',
    run: (l) =>
        (SlopEmptyCatchRule(projectRoot: tmp.path).run(l)
              ..sort((a, b) => a.line.compareTo(b.line)))
            .map((f) => f.fingerprint)
            .toList(),
  );

  Future<List<String>> ignorePrints(String source) => fingerprints(
    source,
    'slop-unjustified-ignore',
    run: (l) =>
        (SlopUnjustifiedIgnoreRule(projectRoot: tmp.path).run(l)
              ..sort((a, b) => a.line.compareTo(b.line)))
            .map((f) => f.fingerprint)
            .toList(),
  );

  group('slop-empty-catch', () {
    const base = '''
void f() {
  try { g(); } on FormatException catch (e) {}
  try { g(); } catch (e) {}
}
void g() {}
''';

    test(
      'inserting another catch, code and comments before keeps prints',
      () async {
        final before = await catchPrints(base);
        final after = await catchPrints('''
// new leading comment
void f() {
  try { g(); } on StateError catch (e) {}
  print(1);
  try { g(); } on FormatException catch (e) {} // trailing
  try { g(); } catch (e) {}
}
void g() {}
''');
        expect(before, hasLength(2));
        expect(after, hasLength(3));
        expect(after, containsAll(before));
      },
    );

    test('re-formatting leaves prints unchanged', () async {
      final before = await catchPrints(base);
      final after = await catchPrints('''
void f() {
  try {
    g();
  } on FormatException
      catch (e) {
  }
  try { g(); }
  catch (e)
  {}
}
void g() {}
''');
      expect(after, before);
    });

    test(
      'identical catch clauses in one member stay distinguishable',
      () async {
        final prints = await catchPrints('''
void f() {
  try { g(); } catch (e) {}
  try { g(); } catch (e) {}
}
void g() {}
''');
        expect(prints.toSet(), hasLength(2));
      },
    );
  });

  group('slop-unjustified-ignore', () {
    test(
      'adding another ignore before keeps the existing fingerprint',
      () async {
        // Concatenated so the dogfooding scan does not see a real directive.
        const ignoreDirective =
            '// '
            'ignore: avoid_print';
        final before = await ignorePrints('''
void f() {
  $ignoreDirective
  print(1);
}
''');
        final after = await ignorePrints('''
void h() {
  $ignoreDirective
  print(2);
}
void f() {
  $ignoreDirective
  print(1);
}
''');
        expect(before, hasLength(1));
        expect(after, hasLength(2));
        expect(after, contains(before.single));
      },
    );
  });

  group('a11y rules', () {
    Future<List<String>> prints(Rule rule, String source) => fingerprints(
      source,
      rule.ruleId,
      run: (l) => (rule.run(l)..sort((a, b) => a.line.compareTo(b.line)))
          .map((f) => f.fingerprint)
          .toList(),
    );

    const header =
        "import 'package:flutter/widgets.dart';\n"
        'class CustomCard {\n'
        '  const CustomCard({required this.onTap});\n'
        '  final void Function() onTap;\n'
        '}\n';

    // ruleId -> (rule, flagged expression in its own member `target`).
    final cases = <String, (Rule Function(), String)>{
      'a11y-form-field-label': (
        () => A11yFormFieldLabelRule(projectRoot: tmp.path),
        'const TextField()',
      ),
      'a11y-icon-button-label': (
        () => A11yIconButtonLabelRule(projectRoot: tmp.path),
        'const IconButton(icon: Icon(42), onPressed: null)',
      ),
      'a11y-image-label': (
        () => A11yImageLabelRule(projectRoot: tmp.path),
        "Image.asset('a.png')",
      ),
      'a11y-interactive-semantics': (
        () => A11yInteractiveSemanticsRule(projectRoot: tmp.path),
        'CustomCard(onTap: () { one(); })',
      ),
    };

    for (final entry in cases.entries) {
      final (makeRule, expr) = entry.value;
      test(
        '${entry.key}: insertion before and re-formatting keep print',
        () async {
          final rule = makeRule();
          final before = await prints(rule, '''
$header
Object target() => $expr;
void one() {}
''');
          final after = await prints(rule, '''
$header
Object other() => $expr;
Object target() =>
    $expr; // trailing
void one() {}
''');
          expect(before, hasLength(1));
          expect(after, hasLength(2));
          // `other` and `target` have different scopes, so only the target
          // print is expected to survive the insertion.
          expect(after, contains(before.single));
        },
      );
    }
  });

  group('normalizedSource / AnchorCounter', () {
    String src(String code) {
      final unit = parseString(content: code).unit;
      final decl = unit.declarations.single as TopLevelVariableDeclaration;
      return normalizedSource(decl.variables.variables.single.initializer!);
    }

    test('ignores formatting, comments and closure bodies', () {
      expect(
        src('var x = Foo(a: 1, onTap: () { one(); });'),
        src(
          'var x = Foo(\n  a: 1, // note\n  onTap: () { two(); three(); },\n);',
        ),
      );
      expect(src('var x = Foo(a: 1);'), isNot(src('var x = Foo(a: 2);')));
    });

    test('counter separates only identical scope and content', () {
      final c = AnchorCounter();
      final a0 = c.next('m', 'x');
      final b0 = c.next('m', 'y');
      final a1 = c.next('m', 'x');
      expect({a0, b0, a1}, hasLength(3));
      expect(AnchorCounter().next('m', 'y'), b0);
    });
  });
}
