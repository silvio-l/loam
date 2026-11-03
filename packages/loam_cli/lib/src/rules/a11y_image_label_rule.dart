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

/// Detects Flutter `Image` widgets without an accessible label (WCAG 1.1.1).
///
/// Rule ID: `a11y-image-label`
///
/// A finding is emitted for every `InstanceCreationExpression` that resolves to
/// Flutter's `Image` class (package URI `package:flutter/…`) and has **neither**
/// a `semanticLabel` named argument (any value, including empty string) **nor**
/// `excludeFromSemantics: true`, and that is not under a Flutter
/// `Semantics(label: …)`, `Semantics(excludeSemantics: true)` or
/// `ExcludeSemantics` ancestor. Dot shorthand (`Image logo = .asset(…)`) is
/// treated like `Image.asset(…)`.
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
/// `computeFingerprint(ruleId, relativePath, anchor)` with the anchor
/// `enclosingMemberName:constructorVariant:contentHash:n` — `contentHash`
/// covers the `Image` expression's normalised tokens (closure bodies
/// collapsed, comments and formatting ignored) and `n` counts only earlier
/// identical expressions in the same member. Line shifts, inserted code and
/// re-formatting leave it unchanged.
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

      final relativePath = projectRelativePosixPath(file.path, projectRoot);

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
  final AnchorCounter _anchors = AnchorCounter();

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Recurse into nested expressions first (process inner nodes before outer).
    super.visitInstanceCreationExpression(node);
    final classEl = constructedClass(node);
    if (classEl == null) return; // unresolved
    _check(
      node,
      classEl,
      node.argumentList,
      node.constructorName.name?.name ?? '',
    );
  }

  /// Dot shorthand: `Image logo = .asset('a.png');`.
  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    super.visitDotShorthandConstructorInvocation(node);
    final classEl = node.constructorName.element;
    final cls = classEl is ConstructorElement ? classEl.enclosingElement : null;
    if (cls == null) return; // unresolved
    _check(node, cls, node.argumentList, node.constructorName.name);
  }

  void _check(
    Expression node,
    InterfaceElement classEl,
    ArgumentList args,
    String variant,
  ) {
    // Check: is this Flutter's Image class?
    if (!isFlutterClass(classEl, 'Image')) return;

    // Check: does this call supply a semanticLabel (any value)?
    if (hasNamedArgument(args, 'semanticLabel')) return;

    // Check: is excludeFromSemantics explicitly set to the boolean literal true?
    if (isTrueNamedArgument(args, 'excludeFromSemantics')) return;

    // Check: a Semantics(label:)/excludeSemantics/ExcludeSemantics ancestor.
    if (hasNamingAncestor(node, excludingCounts: true)) return;

    // Build a position-robust fingerprint using the enclosing member's name.
    final enclosingName = enclosingMemberName(node);
    final anchor = _anchors.next(
      '$enclosingName:${variant.isEmpty ? "new" : variant}',
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
            'Image${variant.isEmpty ? "()" : ".$variant()"} without '
            'semanticLabel or excludeFromSemantics: true '
            '(WCAG 1.1.1 Non-text Content)',
        fingerprint: fingerprint,
        kind: 'missing-semantic-label',
        remedy:
            'Add semanticLabel: "<description>" so screen readers can announce '
            'the image, or wrap it in Semantics(label: "<description>"). For '
            'purely decorative images that carry no information, use '
            'excludeFromSemantics: true or wrap it in ExcludeSemantics instead.',
        wcagRef: WcagRef.wcag111,
      ),
    );
  }
}
