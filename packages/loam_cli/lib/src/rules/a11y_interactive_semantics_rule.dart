import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects interactive custom widgets without an accessible name (WCAG 4.1.2).
///
/// Rule ID: `a11y-interactive-semantics`
///
/// A finding is emitted for every `InstanceCreationExpression` whose resolved
/// class is **not** one of the Flutter built-in interactive widgets already
/// covered by sibling rules and that:
/// - has a named argument `onTap`, `onPressed`, or `onLongPress` (indicating
///   the widget is interactive), **and**
/// - has no enclosing `Semantics(label: …)` ancestor at any depth.
///
/// **Overlap exclusion (conservative, no double-counting):**
/// **All** Flutter built-in classes (library URI `package:flutter/…`) are
/// excluded from this rule:
/// - `IconButton`, `GestureDetector`, `InkWell` — covered by
///   `a11y-icon-button-label`.
/// - `TextField`, `TextFormField` — covered by `a11y-form-field-label`.
/// - `ButtonStyleButton` subclasses (`ElevatedButton`, `TextButton`,
///   `FilledButton`, `OutlinedButton`) — Flutter derives their accessible
///   name from their `child:` text widget via automatic semantics merging.
/// - `FloatingActionButton`, `ListTile` — similar: accessible name is
///   provided through `child:` / `title:` semantics internally.
/// - `Semantics` — is itself the accessibility provider; flagging it would
///   be circular.
///
/// This rule therefore targets **only user-defined and third-party widgets**
/// — classes whose resolved library URI is NOT `package:flutter`.
///
/// **What AST detection does NOT catch (documented limitations):**
/// - Widgets that become interactive at runtime via inherited callbacks
///   (e.g. via `InheritedWidget` or `Provider`).
/// - Interactive behaviour derived from custom gesture recognisers that bypass
///   `onTap`/`onPressed`/`onLongPress` parameter names.
/// - Callback parameters receiving `null` at runtime are still flagged when
///   the named arg is present in the AST (conservative by design).
/// - Custom accessible-name mechanisms other than `Semantics(label: …)` — e.g.
///   `MergeSemantics`, `ExcludeSemantics`, platform views — are not recognised.
///
/// **Element-model check (Invariant 1 — semantics over syntax):**
/// The overlap exclusion uses the resolved library URI of the widget's class:
/// `constructorName.element?.enclosingElement.library?.uri` must NOT be in
/// `package:flutter` for the rule to fire. No string/regex matching on source
/// text is performed.
///
/// **Generated-file exclusion:**
/// Files matched by [isGeneratedDartFile] (`*.g.dart`, `*.freezed.dart`, etc.)
/// are skipped entirely.
///
/// **Fingerprint semantics:**
/// `computeFingerprint(ruleId, relativePath,
///   enclosingMemberName + ':' + widgetName + ':' + occurrenceIndex)` —
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
/// `// loam-ignore: a11y-interactive-semantics – <reason>` on or before the
/// line of the offending widget suppresses the finding.
class A11yInteractiveSemanticsRule implements Rule {
  /// The stable rule ID for [A11yInteractiveSemanticsRule].
  ///
  /// Exposed as a static constant so callers can filter findings by rule ID
  /// without instantiating the rule or risking a typo.
  static const String ruleIdStatic = 'a11y-interactive-semantics';

  /// Creates an [A11yInteractiveSemanticsRule] rooted at [projectRoot].
  ///
  /// [projectRoot] is the absolute path of the analysed package.
  const A11yInteractiveSemanticsRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => 'a11y-interactive-semantics';

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

      final visitor = _InteractiveSemanticsVisitor(
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

/// AST visitor that collects interactive custom widgets without accessible names.
class _InteractiveSemanticsVisitor extends RecursiveAstVisitor<void> {
  _InteractiveSemanticsVisitor({
    required this.ruleId,
    required this.projectRoot,
    required this.relativePath,
    required this.findings,
  });

  final String ruleId;
  final String projectRoot;
  final String relativePath;
  final List<Finding> findings;

  /// Occurrence counter keyed by `enclosingMemberName:widgetName`.
  ///
  /// Ensures that multiple flagged widgets of the same type within the same
  /// enclosing member get distinct, deterministic fingerprints.
  final Map<String, int> _occurrenceCount = {};

  /// Callback argument names that indicate an interactive widget.
  static const _callbackArgs = {'onTap', 'onPressed', 'onLongPress'};

  // (No exclusion name-list needed — all package:flutter classes are excluded
  // by _isExcludedFlutterClass via the resolved library URI check.)

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Recurse into nested expressions first (process inner nodes before outer).
    super.visitInstanceCreationExpression(node);

    // Resolve the constructor via the element model.
    final constructorEl = node.constructorName.element;
    if (constructorEl == null) return; // unresolved

    final classEl = constructorEl.enclosingElement;

    // Skip Flutter built-in interactive widgets covered by sibling rules.
    if (_isExcludedFlutterClass(classEl)) return;

    // Does this call carry any callback arg indicating interactivity?
    if (!_hasInteractiveCallback(node)) return;

    // Suppressed by a Semantics(label: …) ancestor?
    if (_isWrappedInSemanticsLabel(node)) return;

    _addFinding(node, widgetName: classEl.name ?? '<unknown>');
  }

  /// Returns `true` when [classEl] is any Flutter built-in widget, i.e. its
  /// resolved library URI is `package:flutter/…`.
  ///
  /// All Flutter built-in classes are excluded from this rule — they either
  /// derive accessible names from their children automatically (buttons,
  /// ListTile) or are themselves the accessibility primitive (Semantics).
  /// Dedicated sibling rules cover the specific patterns (icon-button-label,
  /// form-field-label). Uses the resolved library URI — never a string/regex
  /// match on source text (Invariant 1: semantics over syntax).
  bool _isExcludedFlutterClass(InterfaceElement classEl) {
    final libUri = classEl.enclosingElement.uri;
    return libUri.scheme == 'package' &&
        libUri.pathSegments.isNotEmpty &&
        libUri.pathSegments.first == 'flutter';
  }

  /// Returns `true` when [node] has at least one named argument whose name is
  /// in [_callbackArgs].
  bool _hasInteractiveCallback(InstanceCreationExpression node) {
    return node.argumentList.arguments.any(
      (arg) => arg is NamedArgument && _callbackArgs.contains(arg.name.lexeme),
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
          if (_isFlutterSemantics(classEl) && _hasArg(current, 'label')) {
            return true;
          }
        }
      }
      current = current.parent;
    }
    return false;
  }

  /// Returns `true` when [classEl] is Flutter's `Semantics` class.
  bool _isFlutterSemantics(InterfaceElement classEl) {
    if (classEl.name != 'Semantics') return false;
    final libUri = classEl.enclosingElement.uri;
    return libUri.scheme == 'package' &&
        libUri.pathSegments.isNotEmpty &&
        libUri.pathSegments.first == 'flutter';
  }

  /// Returns `true` when [node] has a named argument with [argName].
  bool _hasArg(InstanceCreationExpression node, String argName) {
    return node.argumentList.arguments.any(
      (arg) => arg is NamedArgument && arg.name.lexeme == argName,
    );
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

  /// Emits a finding for [node] with [widgetName].
  void _addFinding(
    InstanceCreationExpression node, {
    required String widgetName,
  }) {
    final enclosingName = _enclosingMemberName(node);
    final counterKey = '$enclosingName:$widgetName';
    final idx = _occurrenceCount[counterKey] ?? 0;
    _occurrenceCount[counterKey] = idx + 1;

    final anchor = '$enclosingName:$widgetName:$idx';
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
            '$widgetName with interactive callback but without '
            'Semantics(label: …) — screen readers have no accessible '
            'name for this widget '
            '(WCAG 4.1.2 Name, Role, Value)',
        fingerprint: fingerprint,
        kind: 'missing-accessible-name',
        remedy:
            "Wrap the widget with Semantics(label: '<label>', button: true) "
            'so screen readers can announce its purpose. Alternatively, '
            'add a semantic label through a named property the widget '
            'explicitly supports.',
        wcagRef: WcagRef.wcag412,
      ),
    );
  }
}
