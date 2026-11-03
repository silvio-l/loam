import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../config/loam_config.dart';
import '../loader/project_loader.dart';
import '../model/anchor.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import '../model/project_path.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects production functions and methods whose entire body is
/// `throw UnimplementedError(...)` — a stub an AI agent left behind instead of
/// the implementation.
///
/// Rule ID: `slop-unimplemented-stub`
///
/// The thrown type is recognised on the parsed tree by its name
/// (`UnimplementedError`, so the rule needs no resolution and is a
/// [FileRule]); a file that declares its own class of that name, or
/// `UnsupportedError`/`StateError` (deliberate, documented failures), never
/// match. A finding is emitted for a top-level function, method, getter or
/// setter in a source directory (default `lib`, `bin`) when its body is only
/// the throw (`=> throw …` or `{ throw …; }`).
///
/// What this rule deliberately does **NOT** catch:
/// - A `throw UnimplementedError()` among other statements — a `default:`
///   branch of a `switch` is a legitimate "unsupported value" marker.
/// - Members of `abstract`/`sealed` classes and of mixins: a template method
///   that subclasses must override is by design.
/// - Members of classes that extend `PlatformInterface` (directly or through
///   classes of the same file): the Flutter plugin template ships exactly
///   such defaults on purpose. A chain that leaves the file is not followed
///   (the rule stays on the parse path); it is exempt when the first foreign
///   superclass is `PlatformInterface`, is named `…Platform`, or the file
///   imports a `…platform_interface` library — a missed stub beats a false
///   alarm.
/// - Files outside the source directories (tests, tools) and generated files.
///
/// **Semantic anchor (fingerprint stability):**
/// `Owner.member:unimplemented-stub` (getters `get m`, setters `set m`), plus
/// `:n` only for a repeated name — independent of line numbers and of the
/// message passed to the error.
///
/// **Finding contract:** `severity`: [Severity.warning], `kind`:
/// `'unimplemented-stub'`, `remedy`: imperative fix instruction.
///
/// **Suppression:**
/// `// loam-ignore: slop-unimplemented-stub – <reason>` on or before the
/// member's name line.
class SlopUnimplementedStubRule implements FileRule {
  /// The stable rule ID for [SlopUnimplementedStubRule].
  static const String ruleIdStatic = 'slop-unimplemented-stub';

  /// Creates a [SlopUnimplementedStubRule] rooted at [projectRoot].
  const SlopUnimplementedStubRule({
    required this.projectRoot,
    this.sourceDirs = kDefaultSourceDirs,
  });

  /// Absolute path of the project being analysed.
  final String projectRoot;

  /// Top-level directories that count as production code.
  final List<String> sourceDirs;

  @override
  String get ruleId => ruleIdStatic;

  @override
  RuleCategory get category => RuleCategory.slop;

  @override
  List<Finding> run(ProjectLoadResult result) => runPerFile(this, result);

  @override
  List<Finding> runFile(LoadedFile file) {
    if (isGeneratedDartFile(file.path)) return const [];

    final relativePath = projectRelativePosixPath(file.path, projectRoot);
    final firstSegment = relativePath.split('/').first;
    if (!relativePath.contains('/') || !sourceDirs.contains(firstSegment)) {
      return const [];
    }

    final unit = file.parsed.unit;
    final findings = <Finding>[];
    unit.accept(
      _StubVisitor(
        ruleId: ruleId,
        relativePath: relativePath,
        lineInfo: unit.lineInfo,
        findings: findings,
        platformImport: unit.directives.whereType<ImportDirective>().any(
          (d) => (d.uri.stringValue ?? '').contains('platform_interface'),
        ),
        sameFileClasses: {
          for (final declaration in unit.declarations)
            if (declaration is ClassDeclaration)
              declaration.namePart.typeName.lexeme: declaration,
        },
      ),
    );
    return findings;
  }
}

class _StubVisitor extends RecursiveAstVisitor<void> {
  _StubVisitor({
    required this.ruleId,
    required this.relativePath,
    required this.lineInfo,
    required this.findings,
    required this.sameFileClasses,
    required this.platformImport,
  });

  final String ruleId;
  final String relativePath;
  final LineInfo lineInfo;
  final List<Finding> findings;
  final Map<String, ClassDeclaration> sameFileClasses;

  /// Whether the file imports a `…platform_interface` library.
  final bool platformImport;

  final Map<String, int> _occurrences = {};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final parent = node.parent;
    // Class members sit in a body node; the declaration is one level up.
    final owner = parent is ClassBody ? parent.parent : parent;
    if (_isTemplateOwner(owner, sameFileClasses, platformImport)) return;
    _check(
      body: node.body,
      isGetter: node.isGetter,
      isSetter: node.isSetter,
      name: node.name,
      ownerName: ownerTypeName(node),
    );
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      _check(
        body: node.functionExpression.body,
        isGetter: node.isGetter,
        isSetter: node.isSetter,
        name: node.name,
        ownerName: '',
      );
    }
    super.visitFunctionDeclaration(node);
  }

  void _check({
    required FunctionBody body,
    required bool isGetter,
    required bool isSetter,
    required Token name,
    required String ownerName,
  }) {
    if (!_isUnimplementedStub(body, sameFileClasses)) return;

    final member =
        '${isGetter
            ? 'get '
            : isSetter
            ? 'set '
            : ''}${name.lexeme}';
    final qualified = ownerName.isEmpty ? member : '$ownerName.$member';
    final key = '$qualified:unimplemented-stub';
    final idx = _occurrences[key] ?? 0;
    _occurrences[key] = idx + 1;
    final anchor = idx == 0 ? key : '$key:$idx';

    final location = lineInfo.getLocation(name.offset);
    findings.add(
      Finding(
        ruleId: ruleId,
        severity: Severity.warning,
        filePath: relativePath,
        line: location.lineNumber,
        column: location.columnNumber,
        message:
            '`$qualified` consists only of `throw UnimplementedError(…)` — '
            'a stub in production code that crashes when it is called.',
        fingerprint: computeFingerprint(
          ruleId: ruleId,
          relativePath: relativePath,
          semanticAnchor: anchor,
        ),
        kind: 'unimplemented-stub',
        remedy:
            'Implement the member. If it is intentionally unsupported, make '
            'that explicit with `UnsupportedError` and a reason, make the '
            'member abstract, or suppress with '
            '`// loam-ignore: slop-unimplemented-stub – <reason>`.',
      ),
    );
  }

  /// Whether the whole body is a single `throw UnimplementedError(…)`.
  ///
  /// Works on the parsed tree (no resolution): the thrown type is recognised
  /// by its unqualified name, unless the file declares its own class of that
  /// name.
  static bool _isUnimplementedStub(
    FunctionBody body,
    Map<String, ClassDeclaration> sameFileClasses,
  ) {
    if (sameFileClasses.containsKey(_errorName)) return false;
    Expression? expression;
    if (body is ExpressionFunctionBody) {
      expression = body.expression;
    } else if (body is BlockFunctionBody && body.block.statements.length == 1) {
      final statement = body.block.statements.single;
      if (statement is ExpressionStatement) expression = statement.expression;
    }
    if (expression is! ThrowExpression) return false;
    final thrown = expression.expression;
    return switch (thrown) {
      InstanceCreationExpression() =>
        thrown.constructorName.type.name.lexeme == _errorName,
      MethodInvocation() =>
        thrown.target == null && thrown.methodName.name == _errorName,
      _ => false,
    };
  }

  static const String _errorName = 'UnimplementedError';

  /// Abstract/sealed classes and mixins hold template members on purpose; a
  /// class extending `PlatformInterface` (directly or through classes of the
  /// same file) follows the Flutter plugin template.
  static bool _isTemplateOwner(
    AstNode? owner,
    Map<String, ClassDeclaration> sameFileClasses,
    bool platformImport,
  ) {
    if (owner is MixinDeclaration) return true;
    if (owner is ClassDeclaration && owner.mixinKeyword != null) return true;
    if (owner is ClassDeclaration) {
      if (owner.abstractKeyword != null || owner.sealedKeyword != null) {
        return true;
      }
      final seen = <String>{};
      ClassDeclaration? current = owner;
      while (current != null) {
        final superName = current.extendsClause?.superclass.name.lexeme;
        if (superName == null) break;
        if (superName == 'PlatformInterface') return true;
        if (!seen.add(superName)) break;
        final next = sameFileClasses[superName];
        if (next == null) {
          // The chain leaves the file: assume the platform-interface pattern
          // on a strong hint instead of resolving the other file.
          return superName.endsWith('Platform') || platformImport;
        }
        current = next;
      }
    }
    return false;
  }
}
