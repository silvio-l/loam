import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

/// Shared element-model helpers for the A11y rules that decide whether a
/// widget already has an accessible name (invariant 1: semantics over syntax).
///
/// Every type check resolves the class through the element model and accepts
/// only classes declared in `package:flutter`; a project class that happens to
/// share a name never counts.

/// Returns `true` when [classEl] is Flutter's class with the given [name].
bool isFlutterClass(InterfaceElement classEl, String name) {
  if (classEl.name != name) return false;
  final libUri = classEl.enclosingElement.uri;
  return libUri.scheme == 'package' &&
      libUri.pathSegments.isNotEmpty &&
      libUri.pathSegments.first == 'flutter';
}

/// Returns the named argument [name] of [args], or `null` when absent.
NamedArgument? namedArgument(ArgumentList args, String name) {
  for (final arg in args.arguments) {
    if (arg is NamedArgument && arg.name.lexeme == name) return arg;
  }
  return null;
}

/// Returns `true` when [args] carries a named argument [name].
bool hasNamedArgument(ArgumentList args, String name) =>
    namedArgument(args, name) != null;

/// Returns `true` when [args] sets [name] to the boolean literal `true`.
bool isTrueNamedArgument(ArgumentList args, String name) {
  final value = namedArgument(args, name)?.argumentExpression;
  return value is BooleanLiteral && value.value;
}

/// The Flutter class instantiated by [node], or `null` when [node] is not a
/// resolved constructor call.
InterfaceElement? constructedClass(InstanceCreationExpression node) =>
    node.constructorName.element?.enclosingElement;

/// Returns `true` when the `icon:`/`child:` argument [argName] of [args] is a
/// Flutter `Icon(…)` that carries a `semanticLabel`.
bool hasLabelledIcon(ArgumentList args, String argName) {
  final value = namedArgument(args, argName)?.argumentExpression;
  if (value is! InstanceCreationExpression) return false;
  final cls = constructedClass(value);
  return cls != null &&
      isFlutterClass(cls, 'Icon') &&
      hasNamedArgument(value.argumentList, 'semanticLabel');
}

/// Returns `true` when an ancestor of [node] (any depth) names it for
/// assistive technology.
///
/// Always counted: Flutter `Semantics(label: …)`. With [tooltipCounts] also
/// `Tooltip(message: …)` (it announces its message for the subtree). With
/// [excludingCounts] also `Semantics(excludeSemantics: true)` and
/// `ExcludeSemantics` (without `excluding: false`), which deliberately remove
/// the subtree from the semantics tree.
bool hasNamingAncestor(
  AstNode node, {
  bool tooltipCounts = false,
  bool excludingCounts = false,
}) {
  AstNode? current = node.parent;
  while (current != null) {
    if (current is InstanceCreationExpression) {
      final cls = constructedClass(current);
      if (cls != null) {
        final args = current.argumentList;
        if (isFlutterClass(cls, 'Semantics') &&
            (hasNamedArgument(args, 'label') ||
                (excludingCounts &&
                    isTrueNamedArgument(args, 'excludeSemantics')))) {
          return true;
        }
        if (tooltipCounts &&
            isFlutterClass(cls, 'Tooltip') &&
            hasNamedArgument(args, 'message')) {
          return true;
        }
        if (excludingCounts &&
            isFlutterClass(cls, 'ExcludeSemantics') &&
            !_isFalseNamedArgument(args, 'excluding')) {
          return true;
        }
      }
    }
    current = current.parent;
  }
  return false;
}

bool _isFalseNamedArgument(ArgumentList args, String name) {
  final value = namedArgument(args, name)?.argumentExpression;
  return value is BooleanLiteral && !value.value;
}
