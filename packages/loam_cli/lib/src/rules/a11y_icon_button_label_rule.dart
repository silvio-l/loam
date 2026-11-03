import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../loader/project_loader.dart';
import '../model/anchor.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import '../model/project_path.dart';
import 'a11y_name_sources.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects Flutter interactive widgets without an accessible name (WCAG 4.1.2).
///
/// Rule ID: `a11y-icon-button-label`
///
/// A finding is emitted for:
/// - [IconButton] that has **neither** a `tooltip` named argument, an `Icon`
///   with a `semanticLabel`, **nor** an enclosing `Semantics(label:)` or
///   `Tooltip(message:)` ancestor.
/// - [GestureDetector] or [InkWell] whose direct `child` argument resolves to
///   Flutter's [Icon] widget and that likewise has no enclosing
///   `Semantics(label: …)` ancestor.
///
/// Conservative rule: any of the following suppresses the finding:
/// - `IconButton(tooltip: '…')` — tooltip provides the accessible name.
/// - An `Icon(…, semanticLabel: …)` as the `icon:`/`child:`.
/// - A `Semantics(label: '…')` or `Tooltip(message: '…')` ancestor (any depth)
///   around the widget (`IconButton` builds its own `Tooltip` from `tooltip:`).
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
/// `computeFingerprint(ruleId, relativePath, anchor)` with the anchor
/// `enclosingMemberName:widgetKind:contentHash:n` — `contentHash` covers the
/// widget's normalised tokens (closure bodies collapsed, comments and
/// formatting ignored) and `n` counts only earlier identical widgets in the
/// same member. Inserting code or comments elsewhere, line shifts and
/// re-formatting leave it unchanged.
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
  List<Finding> run(ProjectLoadResult result) {
    final findings = <Finding>[];

    for (final file in result.resolved) {
      // Skip generated files — *.g.dart, *.freezed.dart, *.mocks.dart, gen-l10n.
      if (isGeneratedDartFile(file.path)) continue;

      final relativePath = projectRelativePosixPath(file.path, projectRoot);

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

  final AnchorCounter _anchors = AnchorCounter();

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Recurse into nested expressions first (process inner nodes before outer).
    super.visitInstanceCreationExpression(node);

    // Resolve the constructor via the element model.
    final constructorEl = node.constructorName.element;
    if (constructorEl == null) return; // unresolved

    final classEl = constructorEl.enclosingElement;

    if (isFlutterClass(classEl, 'IconButton')) {
      // An IconButton is accessible when it has a tooltip or a Semantics
      // ancestor with a non-null label.
      if (hasNamedArgument(node.argumentList, 'tooltip')) return;
      if (hasLabelledIcon(node.argumentList, 'icon')) return;
      if (hasNamingAncestor(node, tooltipCounts: true)) return;
      _addFinding(
        node,
        widgetKind: 'IconButton',
        message:
            'IconButton without tooltip and without Semantics(label:) '
            '— screen readers have no accessible name '
            '(WCAG 4.1.2 Name, Role, Value)',
      );
    } else if (isFlutterClass(classEl, 'GestureDetector') ||
        isFlutterClass(classEl, 'InkWell')) {
      // A GestureDetector/InkWell is flagged only when its child is a pure
      // Flutter Icon and there is no enclosing Semantics label.
      final widgetName = classEl.name ?? 'GestureDetector';
      if (!_childIsPureFlutterIcon(node)) return;
      if (hasLabelledIcon(node.argumentList, 'child')) return;
      if (hasNamingAncestor(node, tooltipCounts: true)) return;
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
          return isFlutterClass(childConstructorEl.enclosingElement, 'Icon');
        }
        return false; // child exists but is not a simple Icon(…)
      }
    }
    return false; // no child argument
  }

  /// Emits a finding for [node], using [widgetKind] and [message].
  void _addFinding(
    InstanceCreationExpression node, {
    required String widgetKind,
    required String message,
  }) {
    final enclosingName = enclosingMemberName(node);
    // Scope + node content (closure bodies collapsed); the counter only
    // separates true duplicates, so insertions elsewhere never shift it.
    final anchor = _anchors.next(
      '$enclosingName:$widgetKind',
      normalizedSource(node),
    );
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
            'can announce its purpose; alternatively give its Icon a '
            "semanticLabel or wrap it in Tooltip(message: '<label>'). For "
            'GestureDetector/InkWell with an Icon child, wrap with '
            "Semantics(label: '<label>') or Tooltip(message: '<label>') "
            'instead.',
        wcagRef: WcagRef.wcag412,
      ),
    );
  }
}
