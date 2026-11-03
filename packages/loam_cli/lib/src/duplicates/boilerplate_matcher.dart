import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Decides whether a method is intentional, mechanically-shaped boilerplate
/// (`copyWith`, `==`, `hashCode`, `toString`, `fromJson`, …) whose body is
/// *meant* to look like its siblings in other classes.
///
/// Detection is structural, on the AST declaration: the member kind (operator,
/// getter, factory constructor, method) and the parameter shape must fit, not
/// just the name. A method that merely happens to be called `copyWith` but
/// takes a positional argument is therefore still analysed.
///
/// Serialisers (`toString`, `toJson`, `toMap`, `fromJson`, `fromMap`) must in
/// addition be plain field mapping: a body with a loop or a `switch`
/// statement carries real logic and is still compared, so a copied
/// serialiser with logic is not hidden. `==`, `hashCode`, `props` and
/// `copyWith` are field-wise by nature and are not body-checked (an
/// `if (identical(this, other))` guard is part of the idiom).
///
/// Names added through `code_duplicates.boilerplate_methods` in `loam.yaml`
/// match by name alone (the user vouches for them).
class BoilerplateMatcher {
  /// Creates a matcher; [extraNames] are matched by name only.
  const BoilerplateMatcher({this.extraNames = const {}}) : enabled = true;

  /// A matcher that never matches (`code_duplicates.boilerplate: false`).
  const BoilerplateMatcher.disabled() : extraNames = const {}, enabled = false;

  /// Whether boilerplate is skipped at all.
  final bool enabled;

  /// Extra method names matched by name only.
  final Set<String> extraNames;

  /// Whether [node] is boilerplate.
  bool isBoilerplateMethod(MethodDeclaration node) {
    if (!enabled) return false;
    final name = node.name.lexeme;
    if (extraNames.contains(name)) return true;
    final params = node.parameters?.parameters ?? const <FormalParameter>[];

    if (node.isOperator) return name == '==' && params.length == 1;
    if (node.isGetter) return name == 'hashCode' || name == 'props';
    if (node.isSetter) return false;

    switch (name) {
      case 'copyWith':
        // copyWith({a, b}): at least one parameter, all named.
        return params.isNotEmpty && params.every((p) => p.isNamed);
      case 'toString':
      case 'toJson':
      case 'toMap':
        // Serialisation reads the receiver only: no required parameters.
        return !params.any((p) => p.isRequired) && _isPlainMapping(node.body);
      case 'fromJson':
      case 'fromMap':
        // static T fromJson(Map<String, dynamic> json)
        return node.isStatic &&
            params.length == 1 &&
            _isPlainMapping(node.body);
    }
    return false;
  }

  /// Whether [node] is a boilerplate constructor
  /// (`factory X.fromJson(json)` / `X.fromMap(map)`).
  bool isBoilerplateConstructor(ConstructorDeclaration node) {
    if (!enabled) return false;
    final name = node.name?.lexeme;
    if (name == null) return false;
    if (extraNames.contains(name)) return true;
    return (name == 'fromJson' || name == 'fromMap') &&
        node.parameters.parameters.length == 1 &&
        _isPlainMapping(node.body);
  }
}

/// Whether [body] maps fields without loops or `switch` statements.
/// Collection `for`/`if` elements in literals stay allowed: they are the
/// idiomatic way to map lists and optional keys.
bool _isPlainMapping(FunctionBody body) {
  final finder = _LogicFinder();
  body.accept(finder);
  return !finder.found;
}

class _LogicFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitForStatement(ForStatement node) => found = true;

  @override
  void visitWhileStatement(WhileStatement node) => found = true;

  @override
  void visitDoStatement(DoStatement node) => found = true;

  @override
  void visitSwitchStatement(SwitchStatement node) => found = true;
}
