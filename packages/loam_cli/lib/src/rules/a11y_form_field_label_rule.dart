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
/// `computeFingerprint(ruleId, relativePath, anchor)` with the anchor
/// `enclosingMemberName:widgetKind:contentHash:n` — `contentHash` covers the
/// widget's normalised tokens (closure bodies collapsed, comments and
/// formatting ignored) and `n` counts only earlier identical widgets in the
/// same member. Inserting code or comments elsewhere, line shifts and
/// re-formatting leave it unchanged.
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

      final relativePath = projectRelativePosixPath(file.path, projectRoot);

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

  final AnchorCounter _anchors = AnchorCounter();

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Recurse into nested expressions first (process inner nodes before outer).
    super.visitInstanceCreationExpression(node);

    // Resolve the constructor via the element model.
    final constructorEl = node.constructorName.element;
    if (constructorEl == null) return; // unresolved

    final classEl = constructorEl.enclosingElement;

    // Only act on Flutter's TextField or TextFormField.
    final isTextField = isFlutterClass(classEl, 'TextField');
    final isTextFormField = isFlutterClass(classEl, 'TextFormField');
    if (!isTextField && !isTextFormField) return;

    final widgetKind = classEl.name ?? 'TextField';

    // Suppressed by a Semantics(label: …) ancestor?
    if (hasNamingAncestor(node)) return;

    // Inspect the decoration: argument.
    final decorationArg = namedArgument(node.argumentList, 'decoration');

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
    if (!isFlutterClass(decoClassEl, 'InputDecoration')) return;

    // InputDecoration present — check for labelText or hintText (fallback).
    final decoArgs = decorationExpr.argumentList;
    if (hasNamedArgument(decoArgs, 'labelText')) return; // clean
    if (hasNamedArgument(decoArgs, 'label')) return; // label: Text(…) is clean
    if (hasNamedArgument(decoArgs, 'hintText')) return; // fallback: clean

    // InputDecoration without label, labelText or hintText — label is missing.
    _addFinding(node, widgetKind: widgetKind);
  }

  /// Emits a finding for [node] with [widgetKind].
  void _addFinding(
    InstanceCreationExpression node, {
    required String widgetKind,
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
        message:
            '$widgetKind without a label — screen readers have no accessible '
            'name for this field '
            '(WCAG 1.3.1 Info and Relationships / 3.3.2 Labels or Instructions'
            ' / 4.1.2 Name, Role, Value)',
        fingerprint: fingerprint,
        kind: 'missing-form-label',
        remedy:
            "Add decoration: InputDecoration(labelText: '<label>') so screen "
            'readers and sighted users can identify the field. hintText is '
            'only a fallback: it disappears once the user types, so use it '
            'only for search or read-only contexts. Alternatively, wrap the '
            "field with Semantics(label: '<label>').",
        wcagRef: WcagRef.wcag332,
      ),
    );
  }
}
