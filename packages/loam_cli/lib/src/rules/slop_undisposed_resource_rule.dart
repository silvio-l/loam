import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../loader/project_loader.dart';
import '../model/anchor.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import '../model/project_path.dart';
import 'generated_file.dart';
import 'rule.dart';

/// A plain [Rule], not a [FileRule]: the check reads resolved elements (the
/// field's type, the `State` supertype), so it needs a full (resolved) load.
///
/// Detects fields that a class creates itself but never releases.
///
/// Rule ID: `slop-undisposed-resource`
///
/// Agents that add a `TextEditingController`, `Timer.periodic` or
/// `ValueNotifier` to a widget `State` often forget the matching line in
/// `dispose()`. The object then keeps its listeners and timers alive after the
/// widget is gone. A finding is emitted for a field of a class that is a
/// Flutter `State` subclass **or** declares its own `dispose()` when
///
/// 1. the class **creates the value itself**: a field initializer or an
///    assignment anywhere in the class (`initState`, a constructor, another
///    method, a constructor initializer list) whose right side is an instance
///    creation, a static factory call (`Timer.periodic(…)`) or a cascade on
///    one — never a parameter, `widget.x`, a provider/`ref`/`context` lookup
///    or any other expression;
/// 2. the field's **resolved static type** has a no-argument instance method
///    `dispose`, `close` or `cancel`, own or inherited (looked up on the
///    element model — there is no list of type names, so
///    `OverlayPortalController`, which has none, is never reported). `close`
///    and `cancel` count only when the Dart SDK or a third-party package
///    declares them: Flutter's and the project's own controllers use them
///    for state changes (`MenuController.close()`), not for release; and
/// 3. `dispose()` does not release it: the field is not referenced anywhere in
///    `dispose()` nor in any method of the same class that `dispose()` calls
///    or tears off, directly or transitively (`_disposeAll()`, a loop, a
///    list literal, `?.dispose()` all count).
///
/// A field that is also assigned a non-created value (`_c = widget.c`) is not
/// owned by the class and is skipped, as are `static` fields and `late`
/// fields that never receive a created value.
///
/// **Semantic anchor (fingerprint stability):**
/// `Class.field:undisposed:contentHash:n` — content is the field's resolved
/// type, `n` counts earlier identical anchors in the same file.
///
/// **Suppression:** `// loam-ignore: slop-undisposed-resource – <reason>`.
class SlopUndisposedResourceRule implements Rule {
  /// The stable rule ID for [SlopUndisposedResourceRule].
  static const String ruleIdStatic = 'slop-undisposed-resource';

  /// Creates a [SlopUndisposedResourceRule] rooted at [projectRoot].
  const SlopUndisposedResourceRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => ruleIdStatic;

  @override
  RuleCategory get category => RuleCategory.slop;

  @override
  List<Finding> run(ProjectLoadResult result) => [
    for (final file in result.resolved)
      if (!isGeneratedDartFile(file.path)) ..._scan(file),
  ];

  List<Finding> _scan(LoadedFile file) {
    final visitor = _ClassVisitor(
      relativePath: projectRelativePosixPath(file.path, projectRoot),
    );
    file.result.unit.accept(visitor);
    return visitor.findings;
  }
}

/// Names of the release methods, in the order they are suggested.
const _releaseMethods = ['dispose', 'close', 'cancel'];

class _ClassVisitor extends RecursiveAstVisitor<void> {
  _ClassVisitor({required this.relativePath});

  final String relativePath;
  final List<Finding> findings = [];
  final AnchorCounter _anchors = AnchorCounter();

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    super.visitClassDeclaration(node);
    final members = _Members.collect(node);
    final element = node.declaredFragment?.element;
    if (element == null) return;
    if (!_isFlutterState(element) && members.dispose == null) return;

    final released = members.releasedFields();
    for (final field in members.fields) {
      final fieldElement = field.declaredFragment?.element;
      if (fieldElement is! FieldElement || fieldElement.isStatic) continue;
      if (!members.ownsCreatedValue(field, fieldElement)) continue;
      final release = _releaseMethodOf(fieldElement.type, element.library);
      if (release == null || released.contains(fieldElement)) continue;
      _report(node, field, fieldElement, release);
    }
  }

  void _report(
    ClassDeclaration cls,
    VariableDeclaration field,
    FieldElement element,
    String release,
  ) {
    final className = cls.namePart.typeName.lexeme;
    final name = field.name.lexeme;
    final typeText = element.type.getDisplayString();
    final fingerprint = computeFingerprint(
      ruleId: SlopUndisposedResourceRule.ruleIdStatic,
      relativePath: relativePath,
      semanticAnchor: _anchors.next('$className.$name:undisposed', typeText),
    );
    final location = (field.root as CompilationUnit).lineInfo.getLocation(
      field.name.offset,
    );
    findings.add(
      Finding(
        ruleId: SlopUndisposedResourceRule.ruleIdStatic,
        severity: Severity.warning,
        filePath: relativePath,
        line: location.lineNumber,
        column: location.columnNumber,
        message:
            '`$name` ($typeText) is created by `$className` but `dispose()` '
            'never calls `$release()` on it — its listeners or timers outlive '
            'the object.',
        fingerprint: fingerprint,
        kind: 'undisposed-resource',
        remedy:
            'Call `$name.$release()` in `dispose()` (before '
            '`super.dispose()` in a `State`). If another object owns it, do '
            'not create it here; if the leak is intentional, suppress with '
            '`// loam-ignore: slop-undisposed-resource – <reason>`.',
      ),
    );
  }
}

/// Whether [cls] has Flutter's `State` among its supertypes.
bool _isFlutterState(ClassElement cls) => cls.allSupertypes.any((t) {
  final uri = t.element.library.uri;
  return t.element.name == 'State' &&
      uri.scheme == 'package' &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == 'flutter';
});

/// The first of `dispose`/`close`/`cancel` that [type] offers as a no-argument
/// instance method (own or inherited), or `null`.
///
/// `dispose` always counts. `close` and `cancel` also name state changes of
/// reusable controllers (`MenuController.close()`, a gesture gate's
/// `cancel()`), so they count only when the method is declared by the Dart
/// SDK (`Timer`, `StreamSubscription`, `StreamController`, `Sink`, sockets …)
/// or by a third-party package — not by Flutter or by [library]'s own package.
String? _releaseMethodOf(DartType type, LibraryElement library) {
  if (type is! InterfaceType) return null;
  for (final name in _releaseMethods) {
    final method = type.lookUpMethod(name, library);
    if (method == null || method.isStatic) continue;
    if (method.formalParameters.any((p) => p.isRequired)) continue;
    if (name != 'dispose' && !_isReleaseDeclaredElsewhere(method, library)) {
      continue;
    }
    return name;
  }
  return null;
}

bool _isReleaseDeclaredElsewhere(MethodElement method, LibraryElement own) {
  final uri = method.library.uri;
  if (uri.scheme == 'dart') return true;
  if (uri.scheme != 'package' || uri.pathSegments.isEmpty) return false;
  final package = uri.pathSegments.first;
  final ownUri = own.uri;
  final ownPackage =
      ownUri.scheme == 'package' && ownUri.pathSegments.isNotEmpty
      ? ownUri.pathSegments.first
      : null;
  return package != 'flutter' && package != ownPackage;
}

/// The field behind [element] (a field itself or its implicit accessor).
FieldElement? _fieldOf(Element? element) => switch (element) {
  FieldElement() => element.baseElement,
  PropertyAccessorElement() => switch (element.variable) {
    final FieldElement f => f.baseElement,
    _ => null,
  },
  _ => null,
};

/// Whether [e] builds a fresh object: an instance creation, a static factory
/// call, or a cascade on one. `const` objects are shared, not owned.
bool _isCreation(Expression? e) => switch (e) {
  InstanceCreationExpression() => !e.isConst,
  DotShorthandConstructorInvocation() => !e.isConst,
  MethodInvocation() =>
    switch (e.methodName.element) {
          MethodElement(isStatic: true) => true,
          _ => false,
        } &&
        e.target != null,
  CascadeExpression() => _isCreation(e.target),
  ParenthesizedExpression() => _isCreation(e.expression),
  _ => false,
};

/// The members of one class that matter for the check.
class _Members {
  _Members._(this.fields, this.methods, this.constructors, this.cls);

  final List<VariableDeclaration> fields;
  final Map<String, MethodDeclaration> methods;
  final List<ConstructorDeclaration> constructors;
  final ClassDeclaration cls;

  /// Per field: has a created value, and has any other assigned value.
  final Map<FieldElement, bool> _created = {};
  final Set<FieldElement> _foreign = {};
  bool _assignmentsScanned = false;

  MethodDeclaration? get dispose {
    final m = methods['dispose'];
    return m != null &&
            !m.isStatic &&
            !m.isGetter &&
            !m.isSetter &&
            (m.parameters?.parameters.isEmpty ?? true)
        ? m
        : null;
  }

  static _Members collect(ClassDeclaration cls) {
    final fields = <VariableDeclaration>[];
    final methods = <String, MethodDeclaration>{};
    final constructors = <ConstructorDeclaration>[];
    cls.visitChildren(_MemberCollector(fields, methods, constructors));
    return _Members._(fields, methods, constructors, cls);
  }

  /// Whether the class creates the value of [field] itself and never stores a
  /// value it does not own in it.
  bool ownsCreatedValue(VariableDeclaration field, FieldElement element) {
    _scanAssignments();
    if (_foreign.contains(element)) return false;
    return _isCreation(field.initializer) || (_created[element] ?? false);
  }

  void _scanAssignments() {
    if (_assignmentsScanned) return;
    _assignmentsScanned = true;
    cls.accept(_AssignmentScanner(this));
  }

  void _record(FieldElement field, Expression value) {
    if (_isCreation(value)) {
      _created[field] = true;
    } else if (value is! NullLiteral) {
      _foreign.add(field);
    }
  }

  /// Fields referenced by `dispose()` or by any method of this class it
  /// reaches through calls and tear-offs.
  Set<FieldElement> releasedFields() {
    final released = <FieldElement>{};
    final start = dispose;
    if (start == null) return released;
    final seen = <String>{'dispose'};
    final queue = [start];
    while (queue.isNotEmpty) {
      final method = queue.removeLast();
      method.accept(
        _ReferenceCollector((SimpleIdentifier id) {
          final element = id.element;
          final field = _fieldOf(element);
          if (field != null) released.add(field);
          if (element is MethodElement && !element.isStatic) {
            final next = methods[element.name];
            if (next != null && seen.add(element.name!)) queue.add(next);
          }
        }),
      );
    }
    return released;
  }
}

class _MemberCollector extends SimpleAstVisitor<void> {
  _MemberCollector(this.fields, this.methods, this.constructors);

  final List<VariableDeclaration> fields;
  final Map<String, MethodDeclaration> methods;
  final List<ConstructorDeclaration> constructors;

  @override
  void visitBlockClassBody(BlockClassBody node) {
    for (final member in node.members) {
      switch (member) {
        case FieldDeclaration():
          fields.addAll(member.fields.variables);
        case MethodDeclaration():
          methods[member.name.lexeme] = member;
        case ConstructorDeclaration():
          constructors.add(member);
        default:
      }
    }
  }
}

class _AssignmentScanner extends RecursiveAstVisitor<void> {
  _AssignmentScanner(this.members);

  final _Members members;

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    super.visitAssignmentExpression(node);
    final field = _fieldOf(node.writeElement);
    if (field == null) return;
    if (node.operator.lexeme == '=') {
      members._record(field, node.rightHandSide);
    } else if (node.operator.lexeme != '??=') {
      members._foreign.add(field);
    } else {
      members._record(field, node.rightHandSide);
    }
  }

  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    super.visitConstructorFieldInitializer(node);
    final field = _fieldOf(node.fieldName.element);
    if (field != null) members._record(field, node.expression);
  }
}

class _ReferenceCollector extends RecursiveAstVisitor<void> {
  _ReferenceCollector(this.onIdentifier);

  final void Function(SimpleIdentifier) onIdentifier;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    onIdentifier(node);
    super.visitSimpleIdentifier(node);
  }
}
