@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:loam/src/duplicates/boilerplate_matcher.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/rules/code_duplicates_rule.dart';
import 'package:loam/src/rules/unused_public_exports_rule.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _fixture(String name) =>
    p.join(Directory.current.path, 'test', 'fixtures', name);

T _first<T extends AstNode>(CompilationUnit unit) {
  final found = <T>[];
  unit.accept(_Collect<T>(found));
  return found.single;
}

class _Collect<T extends AstNode> extends GeneralizingAstVisitor<void> {
  _Collect(this.out);
  final List<T> out;

  @override
  void visitNode(AstNode node) {
    if (node is T) out.add(node);
    super.visitNode(node);
  }
}

void main() {
  group('code-duplicates: boilerplate', () {
    final root = _fixture('boilerplate_fixture');
    late ProjectLoadResult loaded;

    setUpAll(() async {
      loaded = await ProjectLoader().load(root);
      expect(loaded.errors, isEmpty);
    });

    List<Finding> run(BoilerplateMatcher matcher) =>
        CodeDuplicatesRule(projectRoot: root, boilerplate: matcher).run(loaded);

    test('built-in boilerplate is not reported; real duplicates are', () {
      final findings = run(const BoilerplateMatcher());
      // describe() x2 and copyWithPositional() x2 are real duplicates.
      expect(findings, hasLength(2));
    });

    test('disabled matcher reports the boilerplate as before', () {
      final findings = run(const BoilerplateMatcher.disabled());
      // Boilerplate in both classes (fromJson, copyWith, toJson, ==, toString)
      // shows up again on top of the two real duplicates.
      expect(findings.length, greaterThan(2));
      expect(
        findings.length,
        greaterThan(run(const BoilerplateMatcher()).length),
      );
    });

    test('extra names are matched by name only', () {
      final findings = run(const BoilerplateMatcher(extraNames: {'describe'}));
      expect(findings, hasLength(1));
    });
  });

  group('BoilerplateMatcher: structural shape', () {
    const matcher = BoilerplateMatcher();

    bool method(String member) {
      final unit = parseString(content: 'class A {\n$member\n}').unit;
      final decl = _first<MethodDeclaration>(unit);
      return matcher.isBoilerplateMethod(decl);
    }

    bool ctor(String member) {
      final unit = parseString(content: 'class A {\n$member\n}').unit;
      final decl = _first<ConstructorDeclaration>(unit);
      return matcher.isBoilerplateConstructor(decl);
    }

    test('copyWith: named-only matches, positional or empty does not', () {
      expect(method('A copyWith({int? a}) => A();'), isTrue);
      expect(method('A copyWith(int a) => A();'), isFalse);
      expect(method('A copyWith(int a, {int? b}) => A();'), isFalse);
      expect(method('A copyWith() => A();'), isFalse);
    });

    test('toJson/toString/toMap: no required parameter', () {
      expect(method('Map<String, Object?> toJson() => {};'), isTrue);
      expect(method('Map<String, Object?> toJson({int? v}) => {};'), isTrue);
      expect(method('Map<String, Object?> toJson(int depth) => {};'), isFalse);
      expect(
        method('Map<String, Object?> toJson({required int d}) => {};'),
        isFalse,
      );
      expect(method('String toString() => "";'), isTrue);
      expect(method('Map<String, Object?> toMap(int d) => {};'), isFalse);
    });

    test('serialisers: plain mapping matches, loops or switch do not', () {
      // Collection for/if in a literal is idiomatic mapping.
      expect(
        method(
          'Map<String, Object?> toJson() => '
          '{if (a != null) "a": a, "l": [for (final x in l) x]};',
        ),
        isTrue,
      );
      expect(
        method(
          'Map<String, Object?> toJson() { final m = <String, Object?>{}; '
          'for (final x in l) { m[x] = x; } return m; }',
        ),
        isFalse,
      );
      expect(
        method(
          'String toString() { switch (k) { case 1: return "a"; '
          'default: return "b"; } }',
        ),
        isFalse,
      );
      expect(
        method(
          'static A fromJson(Map<String, Object?> j) '
          '{ var i = 0; while (i < 3) { i++; } return A(); }',
        ),
        isFalse,
      );
      expect(
        ctor(
          'factory A.fromMap(Map<String, Object?> m) { do {} while (f); return A(); }',
        ),
        isFalse,
      );
      // == keeps its identical() guard idiom.
      expect(
        method(
          'bool operator ==(Object o) { if (identical(this, o)) return true; '
          'return o is A; }',
        ),
        isTrue,
      );
    });

    test('operator ==: only the one-parameter form', () {
      expect(method('bool operator ==(Object o) => true;'), isTrue);
      expect(method('bool operator ==(Object a, Object b) => true;'), isFalse);
      expect(method('bool operator <(Object o) => true;'), isFalse);
    });

    test('hashCode/props: getters only; other names never match', () {
      expect(method('int get hashCode => 0;'), isTrue);
      expect(method('List<Object?> get props => [];'), isTrue);
      expect(method('int hashCode() => 0;'), isFalse);
      expect(method('set hashCode(int v) {}'), isFalse);
      expect(method('int compute() => 0;'), isFalse);
    });

    test('fromJson/fromMap: static with exactly one parameter', () {
      expect(
        method('static A fromJson(Map<String, Object?> j) => A();'),
        isTrue,
      );
      expect(method('A fromJson(Map<String, Object?> j) => A();'), isFalse);
      expect(method('static A fromJson() => A();'), isFalse);
      expect(method('static A fromMap(Map a, int b) => A();'), isFalse);
    });

    test('constructors: named fromJson/fromMap with one parameter', () {
      expect(ctor('A.fromJson(Map<String, Object?> j);'), isTrue);
      expect(ctor('A.fromMap(Map<String, Object?> j);'), isTrue);
      expect(ctor('A.fromJson(Map j, int v);'), isFalse);
      expect(ctor('A.other(Map j);'), isFalse);
      expect(ctor('A(Map j);'), isFalse);
    });

    test('extra names match by name only; disabled never matches', () {
      const extra = BoilerplateMatcher(extraNames: {'build'});
      final unit = parseString(
        content: 'class A { void build(int x) {} }',
      ).unit;
      final decl = _first<MethodDeclaration>(unit);
      expect(extra.isBoilerplateMethod(decl), isTrue);
      expect(
        const BoilerplateMatcher.disabled().isBoilerplateMethod(decl),
        isFalse,
      );
    });
  });

  group('unused-public-exports: intent annotations', () {
    final root = _fixture('reserved_annotations_fixture');
    late ProjectLoadResult loaded;

    setUpAll(() async {
      loaded = await ProjectLoader().load(root);
      expect(loaded.errors, isEmpty);
    });

    Set<String> names(Set<String> extra) => UnusedPublicExportsRule(
      projectRoot: root,
      extraAnnotations: extra,
    ).run(loaded).map((f) => f.message).toSet();

    test('pragma marker and @protected are exempt, real dead code is not', () {
      final messages = names(const {}).join('\n');
      expect(messages, contains('`TrulyUnused`'));
      expect(messages, contains('`deadMember`'));
      expect(messages, isNot(contains('ReservedByPragma')));
      expect(messages, isNot(contains('`hook`')));
      // Unconfigured custom annotation: still reported.
      expect(messages, contains('ReservedByKeep'));
    });

    test('configured annotation names exempt the symbol', () {
      final messages = names(const {'Keep'}).join('\n');
      expect(messages, isNot(contains('ReservedByKeep')));
      expect(messages, contains('`TrulyUnused`'));
    });
  });
}
