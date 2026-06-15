import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects Flutter interactive widgets without an accessible name (WCAG 4.1.2).
///
/// Rule ID: `a11y-icon-button-label`
///
/// A finding is emitted for:
/// - [IconButton] that has **neither** a `tooltip` named argument **nor** an
///   enclosing [Semantics] ancestor with a non-null `label` argument.
/// - [GestureDetector] or [InkWell] whose direct `child` argument resolves to
///   Flutter's [Icon] widget and that likewise has no enclosing
///   `Semantics(label: …)` ancestor.
///
/// Conservative rule: any of the following suppresses the finding:
/// - `IconButton(tooltip: '…')` — tooltip provides the accessible name.
/// - A `Semantics(label: '…')` ancestor (any depth) around the widget.
///
/// Out of scope (AST-level, not detectable without runtime information):
/// - Composite children that happen to be semantically icon-only at runtime.
/// - Custom button widgets that internally set a semantic label.
/// - `tooltip:` values that are empty strings (conscious author choice).
/// - Dynamic `tooltip` or `label` values computed at runtime.
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
/// - `kind`: `'missing-accessible-name'`
/// - `remedy`: imperative fix instruction
/// - `wcagRef`: [WcagRef.wcag412] (WCAG 4.1.2 Name, Role, Value)
///
/// **Suppression:**
/// `// loam-ignore: a11y-icon-button-label – <reason>` on or before the line
/// of the offending widget suppresses the finding.
class A11yIconButtonLabelRule implements Rule {
  /// The stable rule ID for [A11yIconButtonLabelRule].
  ///
  /// Exposed as a static constant so callers can filter findings by rule ID
  /// without instantiating the rule or risking a typo.
  static const String ruleIdStatic = 'a11y-icon-button-label';

  /// Creates an [A11yIconButtonLabelRule] rooted at [projectRoot].
  ///
  /// [projectRoot] is the absolute path of the analysed package.
  const A11yIconButtonLabelRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => 'a11y-icon-button-label';

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

      final visitor = _IconButtonLabelVisitor(
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

/// AST visitor that collects icon-only interactive widgets without accessible names.
class _IconButtonLabelVisitor extends RecursiveAstVisitor<void> {
  _IconButtonLabelVisitor({
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

    if (_isFlutterClass(classEl, 'IconButton')) {
      // An IconButton is accessible when it has a tooltip or a Semantics
      // ancestor with a non-null label.
      if (_hasArg(node, 'tooltip')) return;
      if (_isWrappedInSemanticsLabel(node)) return;
      _addFinding(
        node,
        widgetKind: 'IconButton',
        message:
            'IconButton without tooltip and without Semantics(label:) '
            '— screen readers have no accessible name '
            '(WCAG 4.1.2 Name, Role, Value)',
      );
    } else if (_isFlutterClass(classEl, 'GestureDetector') ||
        _isFlutterClass(classEl, 'InkWell')) {
      // A GestureDetector/InkWell is flagged only when its child is a pure
      // Flutter Icon and there is no enclosing Semantics label.
      final widgetName = classEl.name ?? 'GestureDetector';
      if (!_childIsPureFlutterIcon(node)) return;
      if (_isWrappedInSemanticsLabel(node)) return;
      _addFinding(
        node,
        widgetKind: widgetName,
        message:
            '$widgetName with Icon child but without Semantics(label:) '
            '— screen readers have no accessible name '
            '(WCAG 4.1.2 Name, Role, Value)',
      );
    }
  }

  /// Returns `true` when [classEl] is Flutter's class with the given [name].
  ///
  /// Uses the resolved library URI — never a string/regex match on the source
  /// (Invariant 1: semantics over syntax). [classEl] is always an
  /// [InterfaceElement] for a [ConstructorElement.enclosingElement].
  bool _isFlutterClass(InterfaceElement classEl, String name) {
    if (classEl.name != name) return false;
    final libUri = classEl.enclosingElement.uri;
    return libUri.scheme == 'package' &&
        libUri.pathSegments.isNotEmpty &&
        libUri.pathSegments.first == 'flutter';
  }

  /// Returns `true` when [node] has a named argument with the given [argName].
  bool _hasArg(InstanceCreationExpression node, String argName) {
    return node.argumentList.arguments.any(
      (arg) => arg is NamedArgument && arg.name.lexeme == argName,
    );
  }

  /// Returns `true` when the direct `child:` argument of [node] is a Flutter
  /// [Icon] instance creation expression.
  ///
  /// Conservative: the child must literally be `Icon(…)` at the AST level.
  /// Composite children (e.g. `Column(children: [Icon(…)])`) are not matched.
  bool _childIsPureFlutterIcon(InstanceCreationExpression node) {
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument && arg.name.lexeme == 'child') {
        final expr = arg.argumentExpression;
        if (expr is InstanceCreationExpression) {
          final childConstructorEl = expr.constructorName.element;
          if (childConstructorEl == null) return false;
          return _isFlutterClass(childConstructorEl.enclosingElement, 'Icon');
        }
        return false; // child exists but is not a simple Icon(…)
      }
    }
    return false; // no child argument
  }

  /// Returns `true` when [node] is enclosed in any `Semantics` ancestor that
  /// has a non-null `label` named argument.
  ///
  /// Walks the parent chain (any depth) looking for an [InstanceCreationExpression]
  /// whose class is Flutter's `Semantics` and that has a `label:` argument.
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
  /// enclosing member is found (e.g. initializer in a top-level variable).
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

  /// Emits a finding for [node], using [widgetKind] and [message].
  void _addFinding(
    InstanceCreationExpression node, {
    required String widgetKind,
    required String message,
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
        message: message,
        fingerprint: fingerprint,
        kind: 'missing-accessible-name',
        remedy:
            "Add tooltip: '<label>' to the IconButton so screen readers "
            'can announce its purpose. For GestureDetector/InkWell with an '
            'Icon child, wrap with Semantics(label: \'<label>\') instead.',
        wcagRef: WcagRef.wcag412,
      ),
    );
  }
}
