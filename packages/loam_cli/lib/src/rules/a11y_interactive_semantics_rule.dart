import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../loader/project_loader.dart';
import '../model/anchor.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import '../model/project_path.dart';
import 'generated_file.dart';
import 'rule.dart';
import 'wrapper_semantics.dart';

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
/// **Call-site accessible-name property (own arguments, no cross-widget
/// analysis):**
/// A finding is also suppressed when the call site itself carries a `label`,
/// `semanticLabel`, or `tooltip` named argument with a non-empty value. This
/// covers custom/third-party widgets that expose an accessible-name-carrying
/// constructor parameter — whether they wrap themselves in
/// `Semantics(label: …)` internally, or delegate the value transitively to an
/// already-excluded Flutter widget (e.g. passing `label` through as a `Text`
/// child of `FilledButton`). Neither case is visible to
/// `_isWrappedInSemanticsLabel`, which only walks the call site's *ancestor*
/// chain — this check inspects the call site's own arguments instead, without
/// ever opening the target class's definition. A literal `null` or empty
/// string (`''`) does not count; any other expression (variable,
/// interpolation, method call, …) is treated as provided, since its runtime
/// value can't be evaluated statically (conservative by design, matching the
/// callback-arg check above).
///
/// **Project-defined wrappers (`wrapper_semantics.dart`):**
/// For a widget class defined in the analysed project with a `build` method
/// (or a `createState` returning a `State` with one), the rule reads the class
/// via the element model instead of trusting the call site's argument names.
/// A name reaching `Semantics(label:)`, `Tooltip`, a `label`/`semanticLabel`/
/// `tooltip` argument of a Flutter widget, a Flutter `Text` inside an
/// interactive element of the wrapper (a `Text` beside an unnamed icon button
/// names nothing) or another project wrapper (followed up to four levels, each
/// class analysed once) is a sink. A wrapper whose sink is independent of
/// its fields labels itself, so call sites need nothing; a sink fed by
/// fields requires the call site to pass the matching constructor argument
/// non-empty (any parameter name). A wrapper that never routes a name to a
/// sink (swallows its `label`) is reported once, at its class declaration,
/// instead of at every call site (a wrapper that only forwards to such a
/// wrapper is not reported again; wrappers that build each other are
/// reported once, at the one with the smallest class key); a call that omits the name of a wrapper
/// that does route one is still reported at the call site. Fields handed to
/// helper methods or unanalysable widgets make the analysis inconclusive and
/// fall back to the call-site check below.
///
/// **What AST detection does NOT catch (documented limitations):**
/// - Widgets that become interactive at runtime via inherited callbacks
///   (e.g. via `InheritedWidget` or `Provider`).
/// - Interactive behaviour derived from custom gesture recognisers that bypass
///   `onTap`/`onPressed`/`onLongPress` parameter names.
/// - Callback parameters receiving `null` at runtime are still flagged when
///   the named arg is present in the AST (conservative by design).
/// - Custom accessible-name mechanisms other than `Semantics(label: …)` and
///   the `label`/`semanticLabel`/`tooltip` call-site properties above — e.g.
///   `MergeSemantics`, `ExcludeSemantics`, platform views — are not
///   recognised.
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
/// `computeFingerprint(ruleId, relativePath, anchor)` with the anchor
/// `enclosingMemberName:widgetName:contentHash:n` — `contentHash` covers the
/// widget's normalised tokens (closure bodies collapsed, comments and
/// formatting ignored) and `n` counts only earlier identical widgets in the
/// same member. Inserting code or comments elsewhere, line shifts and
/// re-formatting leave it unchanged.
///
/// A swallowing wrapper reported at its definition uses the anchor
/// `wrapper:ClassName`, independent of the number of call sites.
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
  // Per-rule boilerplate shared with sibling a11y rules; extracting to a shared base class would add coupling without clarity gain.
  List<Finding> run(ProjectLoadResult result) {
    final findings = <Finding>[];
    // One index and one analysis cache per run, shared by all files.
    final wrappers = WrapperSemantics(result);
    // Swallowing wrappers seen at interactive call sites, by class key.
    final swallowers = <String, WrapperDefinition>{};

    for (final file in result.resolved) {
      // Skip generated files — *.g.dart, *.freezed.dart, *.mocks.dart, gen-l10n.
      if (isGeneratedDartFile(file.path)) continue;

      final relativePath = projectRelativePosixPath(file.path, projectRoot);

      final visitor = _InteractiveSemanticsVisitor(
        ruleId: ruleId,
        projectRoot: projectRoot,
        relativePath: relativePath,
        findings: findings,
        wrappers: wrappers,
        swallowers: swallowers,
      );
      file.result.unit.accept(visitor);
    }

    _reportSwallowers(wrappers, swallowers, findings);
    return findings;
  }
}

extension on A11yInteractiveSemanticsRule {
  /// Emits one finding per swallowing wrapper, at its class declaration.
  ///
  /// A wrapper that only forwards to another swallowing wrapper is skipped:
  /// the fix belongs to the wrapper that actually drops the name. Wrappers
  /// that build each other (a cycle with no way out) are reported once, at the
  /// one with the smallest class key.
  void _reportSwallowers(
    WrapperSemantics wrappers,
    Map<String, WrapperDefinition> swallowers,
    List<Finding> findings,
  ) {
    final keys = swallowers.keys.toSet();
    final ordered = swallowers.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    // Direct "builds" edges between the swallowers, then their closure, so
    // wrappers that build each other are recognised as one cycle.
    final reach = <String, Set<String>>{
      for (final k in keys)
        k: {
          for (final j in keys)
            if (j != k && wrappers.constructsAnyOf(k, {j})) j,
        },
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final from in reach.values) {
        for (final via in from.toList()) {
          final before = from.length;
          from.addAll(reach[via]!);
          if (from.length != before) changed = true;
        }
      }
    }
    for (final def in ordered) {
      final builds = reach[def.key]!;
      // Forwarding to a swallower outside its own cycle: that one is reported.
      if (builds.any((j) => !reach[j]!.contains(def.key))) continue;
      // Mutually building swallowers: one deterministic representative
      // (smallest key) speaks for the whole cycle.
      final cycle = builds.where((j) => reach[j]!.contains(def.key));
      if (cycle.any((j) => j.compareTo(def.key) < 0)) continue;
      final relativePath = projectRelativePosixPath(def.filePath, projectRoot);
      final unit = def.declaration.root;
      final lineInfo = unit is CompilationUnit ? unit.lineInfo : null;
      final location = lineInfo?.getLocation(
        def.declaration.namePart.typeName.offset,
      );
      findings.add(
        Finding(
          ruleId: ruleId,
          severity: Severity.warning,
          filePath: relativePath,
          line: location?.lineNumber ?? 1,
          column: location?.columnNumber,
          message:
              '${def.name} is interactive but never routes a name to '
              'Semantics(label: …), a Tooltip or a Text inside its tapped '
              'area — its callers cannot label it, so screen readers have '
              'no accessible name for it (WCAG 4.1.2 Name, Role, Value)',
          fingerprint: computeFingerprint(
            ruleId: ruleId,
            relativePath: relativePath,
            semanticAnchor: 'wrapper:${def.name}',
          ),
          kind: 'missing-accessible-name',
          remedy:
              'Give ${def.name} an accessible name: take a label parameter '
              'and pass it to Semantics(label: …), Tooltip(message: …) or a '
              'Text inside the tapped area. Fixing it here fixes every call '
              'site.',
          wcagRef: WcagRef.wcag412,
        ),
      );
    }
  }
}

/// AST visitor that collects interactive custom widgets without accessible names.
class _InteractiveSemanticsVisitor extends RecursiveAstVisitor<void> {
  _InteractiveSemanticsVisitor({
    required this.ruleId,
    required this.projectRoot,
    required this.relativePath,
    required this.findings,
    required this.wrappers,
    required this.swallowers,
  });

  final WrapperSemantics wrappers;
  final Map<String, WrapperDefinition> swallowers;
  final String ruleId;
  final String projectRoot;
  final String relativePath;
  final List<Finding> findings;

  final AnchorCounter _anchors = AnchorCounter();

  /// Callback argument names that indicate an interactive widget.
  static const _callbackArgs = {'onTap', 'onPressed', 'onLongPress'};

  /// Named arguments that, when present with a non-empty value on the call
  /// site itself, count as a sufficient accessible name (see the class-level
  /// doc comment "Call-site accessible-name property").
  static const _accessibleNameArgs = {'label', 'semanticLabel', 'tooltip'};

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

    // Project-defined wrapper: judge by what its source does with the name.
    switch (wrappers.coverage(node)) {
      case WrapperNameCoverage.provided:
        return;
      case WrapperNameCoverage.missing:
        _addFinding(node, widgetName: classEl.name ?? '<unknown>');
        return;
      case WrapperNameCoverage.swallowed:
        // Reported once at the definition, not at each call site.
        final def = wrappers.definitionOf(node);
        if (def != null) swallowers.putIfAbsent(def.key, () => def);
        return;
      case WrapperNameCoverage.unknown:
        break;
    }

    // Not analysable: the call site's own label/semanticLabel/tooltip argument.
    if (_hasAccessibleNameProperty(node)) return;

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

  /// Returns `true` when [node]'s own argument list carries a `label`,
  /// `semanticLabel`, or `tooltip` named argument with a non-empty value.
  ///
  /// Inspects only the call site's own arguments — never the definition of
  /// the instantiated class — so it stays cheap and covers both known
  /// false-positive shapes (self-wrapping in `Semantics(...)` internally, or
  /// delegating the value to an already-excluded Flutter widget) without
  /// resolving the target class's body.
  bool _hasAccessibleNameProperty(InstanceCreationExpression node) {
    for (final arg in node.argumentList.arguments) {
      if (arg is! NamedArgument) continue;
      if (!_accessibleNameArgs.contains(arg.name.lexeme)) continue;
      final value = arg.argumentExpression;
      if (value is NullLiteral) continue;
      if (value is SimpleStringLiteral && value.value.isEmpty) continue;
      return true;
    }
    return false;
  }

  /// Returns `true` when [node] is enclosed in any `Semantics` ancestor that
  /// has a non-null `label` named argument.
  ///
  /// Walks the parent chain (any depth) looking for an
  /// [InstanceCreationExpression] whose class is Flutter's `Semantics` and
  /// that has a `label:` argument.
  // Identical helper in each rule's private visitor; a shared mixin would couple unrelated rule files together.
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

  /// Emits a finding for [node] with [widgetName].
  void _addFinding(
    InstanceCreationExpression node, {
    required String widgetName,
  }) {
    final enclosingName = enclosingMemberName(node);
    // Scope + node content (closure bodies collapsed); the counter only
    // separates true duplicates, so insertions elsewhere never shift it.
    final anchor = _anchors.next(
      '$enclosingName:$widgetName',
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
