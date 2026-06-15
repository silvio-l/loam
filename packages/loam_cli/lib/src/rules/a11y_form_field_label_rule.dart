import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects Flutter text input widgets without an accessible label (WCAG 3.3.2).
///
/// Rule ID: `a11y-form-field-label`
///
/// A finding is emitted for every `InstanceCreationExpression` that resolves to
/// Flutter's `TextField` or `TextFormField` class (package URI
/// `package:flutter/…`) and has **none** of the following:
/// - a `decoration:` argument whose value is a `InputDecoration(...)` creation
///   with a non-null `labelText` named argument;
/// - a `decoration:` argument whose value is a `InputDecoration(...)` creation
///   with a non-null `hintText` named argument (accepted as a fallback label);
/// - an enclosing `Semantics(label: …)` ancestor at any depth in the widget tree.
///
/// **Conservative suppression rules:**
/// - Any `decoration:` that is not a literal `InputDecoration(...)` creation
///   (e.g. a variable reference) is left alone — the rule cannot inspect the
///   runtime value, so no false positive is emitted.
/// - Any `Semantics` ancestor with a `label:` argument suppresses the finding,
///   regardless of depth.
///
/// **Out of scope (AST-level, not detectable without runtime information):**
/// - Runtime contrast, focus order, touch-target sizes.
/// - `InputDecoration` instances built from variables or factory methods.
/// - Custom accessible-name mechanisms (e.g. `ExcludeSemantics`, platform views).
///
/// **Element-model check (Invariant 1 — semantics over syntax):**
/// Widget type identity is verified via the resolved element model:
/// `constructorName.element?.enclosingElement` must be an [InterfaceElement]
/// whose `name` matches and whose `library.uri` is in `package:flutter`.
/// No string/regex matching on source text is performed.
///
/// **Generated-file exclusion:**
/// Files matched by [isGeneratedDartFile] (`*.g.dart`, `*.freezed.dart`, etc.)
/// are skipped entirely.
///
/// **Fingerprint semantics:**
/// `computeFingerprint(ruleId, relativePath,
///   enclosingMemberName + ':' + widgetKind + ':' + occurrenceIndex)` —
/// robust against line/column shifts; stable as long as the enclosing
/// function/method name and the occurrence order within it don't change.
///
/// **Finding contract:**
/// - `severity`: [Severity.warning]
/// - `kind`: `'missing-form-label'`
/// - `remedy`: imperative fix instruction
/// - `wcagRef`: [WcagRef.wcag332] (WCAG 3.3.2 Labels or Instructions)
///
/// **Suppression:**
/// `// loam-ignore: a11y-form-field-label – <reason>` on or before the line
/// of the offending widget suppresses the finding.
class A11yFormFieldLabelRule implements Rule {
  /// The stable rule ID for [A11yFormFieldLabelRule].
  ///
  /// Exposed as a static constant so callers can filter findings by rule ID
  /// without instantiating the rule or risking a typo.
  static const String ruleIdStatic = 'a11y-form-field-label';

  /// Creates an [A11yFormFieldLabelRule] rooted at [projectRoot].
  ///
  /// [projectRoot] is the absolute path of the analysed package.
  const A11yFormFieldLabelRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => 'a11y-form-field-label';

  @override
  RuleCategory get category => RuleCategory.accessibility;

  @override
  // loam-ignore: code-duplicates – per-rule boilerplate shared with sibling a11y rules; extracting to a shared base class would add coupling without clarity gain.
  List<Finding> run(ProjectLoadResult result) {
    final findings = <Finding>[];

    for (final file in result.resolved) {
      // Skip generated files — *.g.dart, *.freezed.dart, *.mocks.dart, gen-l10n.
      if (isGeneratedDartFile(file.path)) continue;

      final relativePath = p.relative(file.path, from: projectRoot);

      final visitor = _FormFieldLabelVisitor(
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

/// AST visitor that collects unlabelled Flutter text input widgets.
class _FormFieldLabelVisitor extends RecursiveAstVisitor<void> {
  _FormFieldLabelVisitor({
    required this.ruleId,
    required this.projectRoot,
    required this.relativePath,
    required this.findings,
  });

  final String ruleId;
  final String projectRoot;
  final String relativePath;
  final List<Finding> findings;

  /// Occurrence counter keyed by `enclosingMemberName:widgetKind`.
  ///
  /// Ensures that multiple flagged widgets of the same type within the same
  /// enclosing member get distinct, deterministic fingerprints.
  final Map<String, int> _occurrenceCount = {};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Recurse into nested expressions first (process inner nodes before outer).
    super.visitInstanceCreationExpression(node);

    // Resolve the constructor via the element model.
    final constructorEl = node.constructorName.element;
    if (constructorEl == null) return; // unresolved

    final classEl = constructorEl.enclosingElement;

    // Only act on Flutter's TextField or TextFormField.
    final isTextField = _isFlutterClass(classEl, 'TextField');
    final isTextFormField = _isFlutterClass(classEl, 'TextFormField');
    if (!isTextField && !isTextFormField) return;

    final widgetKind = classEl.name ?? 'TextField';

    // Suppressed by a Semantics(label: …) ancestor?
    if (_isWrappedInSemanticsLabel(node)) return;

    // Inspect the decoration: argument.
    final decorationArg = _namedArgNode(node, 'decoration');

    if (decorationArg == null) {
      // No decoration at all — definitely missing a label.
      _addFinding(node, widgetKind: widgetKind);
      return;
    }

    final decorationExpr = decorationArg.argumentExpression;

    // decoration is not a literal InputDecoration(...) creation — conservative:
    // we cannot inspect the runtime value, so we do not flag (no false positive).
    if (decorationExpr is! InstanceCreationExpression) return;

    final decoConstructorEl = decorationExpr.constructorName.element;
    if (decoConstructorEl == null) return; // unresolved

    final decoClassEl = decoConstructorEl.enclosingElement;

    // decoration value is not Flutter's InputDecoration — leave it alone.
    if (!_isFlutterClass(decoClassEl, 'InputDecoration')) return;

    // InputDecoration present — check for labelText or hintText (fallback).
    if (_hasArg(decorationExpr, 'labelText')) return; // clean
    if (_hasArg(decorationExpr, 'hintText')) return; // hintText fallback: clean

    // InputDecoration without labelText or hintText — label is missing.
    _addFinding(node, widgetKind: widgetKind);
  }

  /// Returns `true` when [classEl] is Flutter's class with the given [name].
  ///
  /// Uses the resolved library URI — never a string/regex match on the source
  /// (Invariant 1: semantics over syntax).
  // loam-ignore: code-duplicates – identical helper in each rule's private visitor; a shared mixin would couple unrelated rule files together.
  bool _isFlutterClass(InterfaceElement classEl, String name) {
    if (classEl.name != name) return false;
    final libUri = classEl.enclosingElement.uri;
    return libUri.scheme == 'package' &&
        libUri.pathSegments.isNotEmpty &&
        libUri.pathSegments.first == 'flutter';
  }

  /// Returns the [NamedArgument] node for [argName], or `null` if absent.
  NamedArgument? _namedArgNode(
    InstanceCreationExpression node,
    String argName,
  ) {
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument && arg.name.lexeme == argName) return arg;
    }
    return null;
  }

  /// Returns `true` when [node] has a named argument with [argName].
  bool _hasArg(InstanceCreationExpression node, String argName) {
    return node.argumentList.arguments.any(
      (arg) => arg is NamedArgument && arg.name.lexeme == argName,
    );
  }

  /// Returns `true` when [node] is enclosed in any `Semantics` ancestor that
  /// has a non-null `label` named argument.
  ///
  /// Walks the parent chain (any depth) looking for an
  /// [InstanceCreationExpression] whose class is Flutter's `Semantics` and
  /// that has a `label:` argument.
  // loam-ignore: code-duplicates – identical helper in each rule's private visitor; a shared mixin would couple unrelated rule files together.
  bool _isWrappedInSemanticsLabel(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is InstanceCreationExpression) {
        final constructorEl = current.constructorName.element;
        if (constructorEl != null) {
          final classEl = constructorEl.enclosingElement;
          if (_isFlutterClass(classEl, 'Semantics') &&
              _hasArg(current, 'label')) {
            return true;
          }
        }
      }
      current = current.parent;
    }
    return false;
  }

  /// Returns the qualified name of the enclosing function or method.
  ///
  /// Used as part of the semantic anchor for fingerprint stability. Walks the
  /// parent chain and returns the first `MethodDeclaration` or
  /// `FunctionDeclaration` name it finds. Returns `'<unknown>'` when no
  /// enclosing member is found.
  // loam-ignore: code-duplicates – identical helper in each rule's private visitor; a shared mixin would couple unrelated rule files together.
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

  /// Emits a finding for [node] with [widgetKind].
  void _addFinding(
    InstanceCreationExpression node, {
    required String widgetKind,
  }) {
    final enclosingName = _enclosingMemberName(node);
    final counterKey = '$enclosingName:$widgetKind';
    final idx = _occurrenceCount[counterKey] ?? 0;
    _occurrenceCount[counterKey] = idx + 1;

    final anchor = '$enclosingName:$widgetKind:$idx';
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
            '$widgetKind without a label — screen readers have no accessible '
            'name for this field '
            '(WCAG 1.3.1 Info and Relationships / 3.3.2 Labels or Instructions'
            ' / 4.1.2 Name, Role, Value)',
        fingerprint: fingerprint,
        kind: 'missing-form-label',
        remedy:
            "Add decoration: InputDecoration(labelText: '<label>') so screen "
            'readers and sighted users can identify the field. For search or '
            "read-only contexts, hintText: '<placeholder>' is accepted as a "
            'fallback. Alternatively, wrap the field with '
            "Semantics(label: '<label>').",
        wcagRef: WcagRef.wcag332,
      ),
    );
  }
}
