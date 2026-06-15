import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects Flutter `Image` widgets without an accessible label (WCAG 1.1.1).
///
/// Rule ID: `a11y-image-label`
///
/// A finding is emitted for every `InstanceCreationExpression` that resolves to
/// Flutter's `Image` class (package URI `package:flutter/…`) and has **neither**
/// a `semanticLabel` named argument (any value, including empty string) **nor**
/// `excludeFromSemantics: true`.
///
/// Covered constructors (all are factory constructors in Flutter):
/// - `Image()` (unnamed)
/// - `Image.asset(...)`
/// - `Image.network(...)`
/// - `Image.file(...)`
/// - `Image.memory(...)`
///
/// Out of scope (AST-level, not detectable here without runtime information):
/// - Runtime contrast, focus order, touch-target sizes.
/// - `Image` subclasses that provide a label through a custom mechanism.
///
/// **Element-model check (Invariant 1 — semantics over syntax):**
/// The rule uses the resolved element model to identify Flutter's `Image`:
/// `constructorName.element?.enclosingElement` must be an `InterfaceElement`
/// whose `name == 'Image'` and whose `library?.uri` is in `package:flutter`.
/// No string/regex matching on source text is performed.
///
/// **Generated-file exclusion:**
/// Files matched by [isGeneratedDartFile] (`*.g.dart`, `*.freezed.dart`, etc.)
/// are skipped entirely.
///
/// **Fingerprint semantics:**
/// `computeFingerprint(ruleId, relativePath, enclosingMemberName + ':' +
/// constructorVariant)` — robust against line/column shifts; stable as long as
/// the enclosing function/method name and the Image constructor variant don't
/// change.
///
/// **Finding contract:**
/// - `severity`: [Severity.warning]
/// - `kind`: `'missing-semantic-label'`
/// - `remedy`: imperative fix instruction
/// - `wcagRef`: [WcagRef.wcag111] (WCAG 1.1.1 Non-text Content)
class A11yImageLabelRule implements Rule {
  /// The stable rule ID for [A11yImageLabelRule].
  ///
  /// Exposed as a static constant so callers can filter findings by rule ID
  /// without instantiating the rule or risking a typo.
  static const String ruleIdStatic = 'a11y-image-label';

  /// Creates an [A11yImageLabelRule] rooted at [projectRoot].
  ///
  /// [projectRoot] is the absolute path of the analysed package.
  const A11yImageLabelRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => 'a11y-image-label';

  @override
  RuleCategory get category => RuleCategory.accessibility;

  @override
  List<Finding> run(ProjectLoadResult result) {
    final findings = <Finding>[];

    for (final file in result.resolved) {
      // Skip generated files — *.g.dart, *.freezed.dart, *.mocks.dart, gen-l10n.
      if (isGeneratedDartFile(file.path)) continue;

      final relativePath = p.relative(file.path, from: projectRoot);

      final visitor = _ImageLabelVisitor(
        ruleId: ruleId,
        projectRoot: projectRoot,
        relativePath: relativePath,
        findings: findings,
      );
      file.result.unit.accept(visitor);
    }

    return findings;
  }
}

/// AST visitor that collects unlabelled Flutter `Image` instantiations.
class _ImageLabelVisitor extends RecursiveAstVisitor<void> {
  _ImageLabelVisitor({
    required this.ruleId,
    required this.projectRoot,
    required this.relativePath,
    required this.findings,
  });

  final String ruleId;
  final String projectRoot;
  final String relativePath;
  final List<Finding> findings;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Recurse into nested expressions first (process inner nodes before outer).
    super.visitInstanceCreationExpression(node);

    // Resolve the constructor via the element model.
    final constructorEl = node.constructorName.element;
    if (constructorEl == null) return; // unresolved

    final classEl = constructorEl.enclosingElement;

    // Check: is this Flutter's Image class?
    if (!_isFlutterImage(classEl)) return;

    // Check: does this call supply a semanticLabel (any value)?
    if (_hasSemanticLabel(node)) return;

    // Check: is excludeFromSemantics explicitly set to the boolean literal true?
    if (_isExcludedFromSemantics(node)) return;

    // Determine the named constructor variant (empty string for unnamed).
    final variant = node.constructorName.name?.name ?? '';

    // Build a position-robust fingerprint using the enclosing member's name.
    final enclosingName = _enclosingMemberName(node);
    final anchor = '$enclosingName:${variant.isEmpty ? "new" : variant}';

    final fingerprint = computeFingerprint(
      ruleId: ruleId,
      relativePath: relativePath,
      semanticAnchor: anchor,
    );

    final location = node.offset;
    final lineInfo = node.root is CompilationUnit
        ? (node.root as CompilationUnit).lineInfo
        : null;
    final line = lineInfo?.getLocation(location).lineNumber ?? 1;
    final column = lineInfo?.getLocation(location).columnNumber;

    findings.add(
      Finding(
        ruleId: ruleId,
        severity: Severity.warning,
        filePath: relativePath,
        line: line,
        column: column,
        message:
            'Image${variant.isEmpty ? "()" : ".$variant()"} without '
            'semanticLabel or excludeFromSemantics: true '
            '(WCAG 1.1.1 Non-text Content)',
        fingerprint: fingerprint,
        kind: 'missing-semantic-label',
        remedy:
            'Add semanticLabel: "<description>" so screen readers can announce '
            'the image. For purely decorative images that carry no information, '
            'use excludeFromSemantics: true instead.',
        wcagRef: WcagRef.wcag111,
      ),
    );
  }

  /// Returns `true` when [classEl] is Flutter's `Image` class.
  ///
  /// Uses the resolved library URI — never a string/regex match on the source
  /// (Invariant 1: semantics over syntax). `enclosingElement` is always
  /// non-null for an [InterfaceElement] (its enclosing library is always known).
  bool _isFlutterImage(InterfaceElement classEl) {
    if (classEl.name != 'Image') return false;
    final libUri = classEl.enclosingElement.uri;
    return libUri.scheme == 'package' &&
        libUri.pathSegments.isNotEmpty &&
        libUri.pathSegments.first == 'flutter';
  }

  /// Returns `true` when [node] has a `semanticLabel` named argument.
  ///
  /// Any value (including an empty string `''`) is accepted — an empty
  /// semanticLabel is a conscious author choice and must not be flagged.
  bool _hasSemanticLabel(InstanceCreationExpression node) {
    return node.argumentList.arguments.any(
      (arg) => arg is NamedArgument && arg.name.lexeme == 'semanticLabel',
    );
  }

  /// Returns `true` when [node] has `excludeFromSemantics: true`.
  ///
  /// Only the boolean literal `true` qualifies — `excludeFromSemantics: false`
  /// (the default) must still be flagged.
  bool _isExcludedFromSemantics(InstanceCreationExpression node) {
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument && arg.name.lexeme == 'excludeFromSemantics') {
        final value = arg.argumentExpression;
        if (value is BooleanLiteral && value.value) return true;
      }
    }
    return false;
  }

  /// Returns the qualified name of the enclosing function or method.
  ///
  /// Used as part of the semantic anchor for fingerprint stability. Walks the
  /// parent chain and returns the first `MethodDeclaration` or
  /// `FunctionDeclaration` name it finds. Returns `'<unknown>'` when no
  /// enclosing member is found (e.g. initializer in a top-level variable).
  String _enclosingMemberName(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is MethodDeclaration) {
        final className =
            (current.parent is ClassDeclaration
                ? (current.parent as ClassDeclaration).namePart.typeName.lexeme
                : null) ??
            '';
        final method = current.name.lexeme;
        return className.isEmpty ? method : '$className.$method';
      }
      if (current is FunctionDeclaration) {
        return current.name.lexeme;
      }
      current = current.parent;
    }
    return '<unknown>';
  }
}
