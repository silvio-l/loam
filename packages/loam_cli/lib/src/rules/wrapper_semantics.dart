import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../loader/project_loader.dart';
import 'generated_file.dart';

/// Whether a project-defined wrapper widget gives a call site an accessible
/// name.
enum WrapperNameCoverage {
  /// The widget's source is not analysable (third-party, no `build`, or the
  /// data flow is too dynamic). Callers keep their syntactic fallback.
  unknown,

  /// The wrapper provides the name itself or the call site supplies the
  /// argument that reaches a semantic sink inside the wrapper.
  provided,

  /// The wrapper routes a name to a sink, but this call site does not pass the
  /// matching argument. The defect is the call site's.
  missing,

  /// The wrapper was analysed conclusively and no name reaches a semantic sink
  /// at all, whatever a call site passes. The defect is the wrapper's, so it
  /// is reported once at the definition ([WrapperSemantics.definitionOf]).
  swallowed,
}

/// Where a project wrapper class is declared.
class WrapperDefinition {
  /// Creates a [WrapperDefinition].
  const WrapperDefinition({
    required this.key,
    required this.name,
    required this.declaration,
    required this.filePath,
  });

  /// Stable identity of the class (library URI and name).
  final String key;

  /// The class name.
  final String name;

  /// The declaring AST node.
  final ClassDeclaration declaration;

  /// Absolute path of the declaring file.
  final String filePath;
}

/// Resolves, via the element model, whether a project-defined widget encapsulates
/// accessible-name semantics (invariant 1: semantics over syntax).
///
/// A *semantic sink* inside the wrapper is one of:
/// - a Flutter `Semantics(label: …)`, `Tooltip(message: …)` or any Flutter
///   widget argument named `label` / `semanticLabel` / `tooltip`,
/// - a Flutter `Text(…)` inside an interactive element of the wrapper (visible
///   text is the accessible name there; beside an unnamed icon button it names
///   nothing),
/// - a call to another project widget whose own analysis reaches a sink.
///
/// If the sink expression is free of the wrapper's own fields, the wrapper
/// labels itself (`selfLabelled`). If it reads fields, the call site must pass
/// the matching constructor argument non-empty. Everything dynamic (fields
/// handed to helper methods or to unanalysable widgets) is *inconclusive* and
/// yields [WrapperNameCoverage.unknown], so false negatives are preferred over
/// false alarms.
///
/// **Bounds:** each class is analysed at most once (cache keyed by library URI
/// and class name), nesting stops at [maxDepth] levels, and cycles are
/// inconclusive. Results truncated by depth or a cycle are not cached.
class WrapperSemantics {
  /// Indexes the class declarations of all non-generated resolved files.
  WrapperSemantics(ProjectLoadResult result) {
    for (final file in result.resolved) {
      if (isGeneratedDartFile(file.path)) continue;
      file.result.unit.accept(_ClassIndexer(_declarations, _paths, file.path));
    }
  }

  /// Maximum number of nested wrapper levels followed.
  static const int maxDepth = 4;

  final Map<String, ClassDeclaration> _declarations = {};
  final Map<String, String> _paths = {};
  final Map<String, _Analysis> _cache = {};
  final Map<String, _Analysis> _topCache = {};
  final Set<String> _inProgress = {};

  /// Judges the call site [call] of a (possibly custom) widget constructor.
  WrapperNameCoverage coverage(InstanceCreationExpression call) {
    final ctor = call.constructorName.element;
    // Factory/redirecting constructors forward arguments to another class:
    // the parameter-to-field mapping is not followed.
    if (ctor == null || ctor.isFactory) return WrapperNameCoverage.unknown;
    try {
      return _coverage(call, ctor);
    } on Object {
      // A single unexpected element/AST shape must not abort the whole run.
      return WrapperNameCoverage.unknown;
    }
  }

  /// The declaration of the project wrapper instantiated by [call], or `null`
  /// for classes outside the analysed project.
  WrapperDefinition? definitionOf(InstanceCreationExpression call) {
    final cls = call.constructorName.element?.enclosingElement;
    if (cls == null) return null;
    final key = _key(cls);
    final decl = _declarations[key];
    final path = _paths[key];
    if (decl == null || path == null) return null;
    return WrapperDefinition(
      key: key,
      name: cls.name ?? '<unknown>',
      declaration: decl,
      filePath: path,
    );
  }

  /// Whether the body of the wrapper [key] (including its `State`) builds an
  /// instance of one of the other classes in [keys].
  bool constructsAnyOf(String key, Set<String> keys) {
    final decl = _declarations[key];
    if (decl == null) return false;
    final roots = <AstNode>[decl];
    final state = _ClassShape.of(decl).createStateTarget(_declarations);
    if (state != null) roots.add(state);
    final probe = _ConstructsProbe(keys.difference({key}));
    for (final root in roots) {
      root.accept(probe);
    }
    return probe.found;
  }

  WrapperNameCoverage _coverage(
    InstanceCreationExpression call,
    ConstructorElement ctor,
  ) {
    final analysis = _analyze(ctor.enclosingElement, 0);
    if (analysis == null || analysis.inconclusive) {
      return WrapperNameCoverage.unknown;
    }
    if (analysis.selfLabelled) return WrapperNameCoverage.provided;
    for (final field in analysis.sinkFields) {
      for (final param in analysis.paramsOf(field, ctor)) {
        if (_callProvides(call, ctor, param)) {
          return WrapperNameCoverage.provided;
        }
      }
    }
    return analysis.sinkFields.isEmpty
        ? WrapperNameCoverage.swallowed
        : WrapperNameCoverage.missing;
  }

  /// Returns `true` when [call] passes a non-empty value for constructor
  /// parameter [paramName].
  bool _callProvides(
    InstanceCreationExpression call,
    ConstructorElement ctor,
    String paramName,
  ) {
    final params = ctor.formalParameters;
    final index = params.indexWhere((p) => p.name == paramName);
    if (index < 0) return false;
    final expr = _argumentFor(call.argumentList.arguments, params, index);
    return expr != null && !_isEmptyValue(expr);
  }

  _Analysis? _analyze(InterfaceElement cls, int depth) {
    final key = _key(cls);
    // Top-level queries always start with an empty stack and full depth
    // budget, so their result (even a truncated one) is canonical and may be
    // memoised without making results depend on query order.
    if (depth == 0) {
      final top = _topCache[key];
      if (top != null) return top;
    }
    final cached = _cache[key];
    if (cached != null) return cached;
    final decl = _declarations[key];
    if (decl == null) return null;
    if (depth > maxDepth || !_inProgress.add(key)) {
      return _Analysis.inconclusiveTransient();
    }
    try {
      final result = _analyzeDeclaration(decl, depth);
      if (!result.transient) _cache[key] = result;
      if (depth == 0) _topCache[key] = result;
      return result;
    } finally {
      _inProgress.remove(key);
    }
  }

  _Analysis _analyzeDeclaration(ClassDeclaration decl, int depth) {
    final shape = _ClassShape.of(decl);
    final roots = <AstNode>[decl];
    // StatefulWidget: the semantics live in the State returned by
    // `createState() => _FooState()`.
    final stateDecl = shape.createStateTarget(_declarations);
    if (stateDecl != null) roots.add(stateDecl);
    if (!shape.hasBuild && stateDecl == null) {
      return _Analysis.inconclusive();
    }
    if (stateDecl != null && !_ClassShape.of(stateDecl).hasBuild) {
      return _Analysis.inconclusive();
    }
    final collector = _SinkCollector(this, shape.fields, depth);
    for (final root in roots) {
      root.accept(collector);
    }
    return _Analysis(
      selfLabelled: collector.selfLabelled,
      sinkFields: collector.sinkFields,
      inconclusive: collector.inconclusive,
      transient: collector.transient,
      fieldParams: shape.fieldParams,
    );
  }

  static String _key(InterfaceElement cls) =>
      '${cls.enclosingElement.uri}#${cls.name}';
}

/// Maps a call site argument list to the expression for formal parameter
/// [index], or `null` when omitted.
Expression? _argumentFor(
  NodeList<Argument> args,
  List<FormalParameterElement> params,
  int index,
) {
  final param = params[index];
  if (param.isNamed) {
    for (final arg in args) {
      if (arg is NamedArgument && arg.name.lexeme == param.name) {
        return arg.argumentExpression;
      }
    }
    return null;
  }
  final positionalIndex = params.take(index).where((p) => !p.isNamed).length;
  final positional = args.where((a) => a is! NamedArgument).toList();
  return positionalIndex < positional.length
      ? positional[positionalIndex] as Expression
      : null;
}

bool _isEmptyValue(Expression value) =>
    value is NullLiteral ||
    (value is SimpleStringLiteral && value.value.isEmpty);

class _Analysis {
  _Analysis({
    required this.selfLabelled,
    required this.sinkFields,
    required this.inconclusive,
    required this.transient,
    required this.fieldParams,
  });

  factory _Analysis.inconclusive() => _Analysis(
    selfLabelled: false,
    sinkFields: const {},
    inconclusive: true,
    transient: false,
    fieldParams: const {},
  );

  factory _Analysis.inconclusiveTransient() => _Analysis(
    selfLabelled: false,
    sinkFields: const {},
    inconclusive: true,
    transient: true,
    fieldParams: const {},
  );

  final bool selfLabelled;
  final Set<String> sinkFields;
  final bool inconclusive;

  /// Truncated by depth or a cycle: valid for this query only, never cached.
  final bool transient;

  /// Field name -> constructor parameter names assigned via initializer list.
  final Map<String, Set<String>> fieldParams;

  /// Constructor parameter names that feed [field] for [ctor]: initializing
  /// formals (`this.field`) plus initializer-list assignments.
  Iterable<String> paramsOf(String field, ConstructorElement ctor) sync* {
    for (final p in ctor.formalParameters) {
      if (p is FieldFormalParameterElement &&
          p.name == field &&
          p.name != null) {
        yield p.name!;
      }
    }
    yield* fieldParams[field] ?? const <String>{};
  }
}

/// Collects fields, initializer assignments and the `build`/`createState`
/// shape of one class.
class _ClassShape extends RecursiveAstVisitor<void> {
  _ClassShape._();

  factory _ClassShape.of(ClassDeclaration decl) {
    final shape = _ClassShape._();
    decl.accept(shape);
    return shape;
  }

  final Set<String> fields = {};
  final Map<String, Set<String>> fieldParams = {};
  bool hasBuild = false;
  Expression? _createStateBody;

  /// Class named by an expression-bodied `createState() => X()`.
  ClassDeclaration? createStateTarget(Map<String, ClassDeclaration> index) {
    final body = _createStateBody;
    if (body is! InstanceCreationExpression) return null;
    final cls = body.constructorName.element?.enclosingElement;
    return cls == null ? null : index[WrapperSemantics._key(cls)];
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    for (final v in node.fields.variables) {
      fields.add(v.name.lexeme);
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    final value = node.expression;
    if (value is SimpleIdentifier) {
      (fieldParams[node.fieldName.name] ??= {}).add(value.name);
    }
    super.visitConstructorFieldInitializer(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (name == 'build') hasBuild = true;
    final body = node.body;
    if (name == 'createState' && body is ExpressionFunctionBody) {
      _createStateBody = body.expression;
    }
    super.visitMethodDeclaration(node);
  }
}

class _ClassIndexer extends RecursiveAstVisitor<void> {
  _ClassIndexer(this.index, this.paths, this.path);

  final Map<String, ClassDeclaration> index;
  final Map<String, String> paths;
  final String path;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element != null) {
      final key = WrapperSemantics._key(element);
      if (!index.containsKey(key)) {
        index[key] = node;
        paths[key] = path;
      }
    }
    super.visitClassDeclaration(node);
  }
}

/// Walks the body of a wrapper class and records which fields reach a
/// semantic sink.
class _SinkCollector extends RecursiveAstVisitor<void> {
  _SinkCollector(this.owner, this.fields, this.depth);

  final WrapperSemantics owner;
  final Set<String> fields;
  final int depth;

  bool selfLabelled = false;
  bool inconclusive = false;
  bool transient = false;
  final Set<String> sinkFields = {};

  /// Sink expressions already accounted for (their inner calls are not
  /// inconclusive).
  final Set<AstNode> _accounted = {};

  static const _nameArgs = {'label', 'semanticLabel', 'tooltip'};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final ctor = node.constructorName.element;
    if (ctor != null) {
      final cls = ctor.enclosingElement;
      if (_isFlutter(cls)) {
        _flutterWidget(node, cls);
      } else {
        _projectWidget(node, ctor);
      }
    }
    super.visitInstanceCreationExpression(node);
    // A field handed to a widget inside a tapped area (typically `child:`) may
    // carry the visible name: the caller decides, so stay inconclusive. Runs
    // after the children so nested sinks are already accounted.
    if (ctor != null &&
        _isFlutter(ctor.enclosingElement) &&
        _isInteractive(node)) {
      _checkOpaqueFields(node);
    }
  }

  void _flutterWidget(InstanceCreationExpression node, InterfaceElement cls) {
    final name = cls.name;
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument) {
        final n = arg.name.lexeme;
        final isSink =
            _nameArgs.contains(n) || (name == 'Tooltip' && n == 'message');
        if (isSink && !_isEmptyValue(arg.argumentExpression)) {
          _sink(arg.argumentExpression);
        }
      } else if (name == 'Text') {
        _text(node, arg as Expression);
      }
    }
  }

  /// A `Text` names the control only inside the tapped area. Elsewhere in
  /// `build` (a sibling of an unnamed icon button) it labels nothing; in a
  /// helper method its place in the tree is unknown.
  void _text(InstanceCreationExpression node, Expression arg) {
    if (_hasInteractiveAncestor(node)) {
      _sink(arg);
    } else if (!_inBuild(node)) {
      inconclusive = true;
    }
  }

  bool _hasInteractiveAncestor(AstNode node) {
    for (AstNode? n = node.parent; n != null; n = n.parent) {
      if (n is InstanceCreationExpression && _isInteractive(n)) return true;
      if (n is ClassDeclaration) return false;
    }
    return false;
  }

  bool _inBuild(AstNode node) {
    for (AstNode? n = node.parent; n != null; n = n.parent) {
      if (n is MethodDeclaration) return n.name.lexeme == 'build';
    }
    return false;
  }

  static const _interactiveArgs = {
    'onTap',
    'onPressed',
    'onLongPress',
    'onDoubleTap',
    'onChanged',
    'onSelected',
  };

  /// Whether [node] carries a callback that makes it an interactive element.
  ///
  /// Deliberately broader than the callbacks the rule's visitor reports on:
  /// `onChanged` and `onSelected` count as interactive here too. A wrong
  /// "interactive" only leaves a wrapper unjudged (no finding), so this errs
  /// on the side of avoiding false alarms.
  bool _isInteractive(InstanceCreationExpression node) =>
      node.argumentList.arguments.any(
        (a) => a is NamedArgument && _interactiveArgs.contains(a.name.lexeme),
      );

  void _checkOpaqueFields(InstanceCreationExpression node) {
    for (final arg in node.argumentList.arguments) {
      if (arg is NamedArgument && _interactiveArgs.contains(arg.name.lexeme)) {
        continue;
      }
      final collector = _FieldRefs(fields, accounted: _accounted);
      arg.accept(collector);
      if (collector.refs.isNotEmpty) {
        inconclusive = true;
        return;
      }
    }
  }

  void _projectWidget(
    InstanceCreationExpression node,
    ConstructorElement ctor,
  ) {
    final params = ctor.formalParameters;
    final args = node.argumentList.arguments;
    final sub = owner._analyze(ctor.enclosingElement, depth + 1);
    for (var i = 0; i < params.length; i++) {
      final expr = _argumentFor(args, params, i);
      if (expr == null) continue;
      final refs = _fieldRefs(expr);
      if (refs.isEmpty) continue;
      _accounted.add(expr);
      if (sub == null || sub.inconclusive) {
        inconclusive = true;
        continue;
      }
      final isSink = sub.sinkFields.any(
        (f) => sub.paramsOf(f, ctor).contains(params[i].name),
      );
      if (isSink) sinkFields.addAll(refs);
    }
    if (sub != null) {
      if (sub.transient) transient = true;
      if (!sub.inconclusive && sub.selfLabelled) selfLabelled = true;
    }
  }

  // Fields handed to helpers or other calls: data flow not followed.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    _noteOpaqueCall(node, node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _noteOpaqueCall(node, node.argumentList);
    super.visitFunctionExpressionInvocation(node);
  }

  void _noteOpaqueCall(AstNode node, ArgumentList args) {
    if (_insideAccounted(node)) return;
    for (final arg in args.arguments) {
      if (_fieldRefs(arg).isNotEmpty) {
        inconclusive = true;
        return;
      }
    }
  }

  bool _insideAccounted(AstNode node) {
    for (AstNode? n = node; n != null; n = n.parent) {
      if (_accounted.contains(n)) return true;
    }
    return false;
  }

  void _sink(Expression expr) {
    _accounted.add(expr);
    final refs = _fieldRefs(expr);
    if (refs.isEmpty) {
      selfLabelled = true;
      return;
    }
    sinkFields.addAll(refs);
    // A fallback (`label ?? 'x'`, `cond ? a : b`) can label the widget even
    // when the argument is omitted.
    final hasFallback = _hasFallback(expr);
    if (hasFallback) selfLabelled = true;
  }

  bool _hasFallback(Expression expr) {
    final probe = _FallbackProbe();
    expr.accept(probe);
    return probe.found;
  }

  Set<String> _fieldRefs(AstNode expr) {
    final collector = _FieldRefs(fields);
    expr.accept(collector);
    return collector.refs;
  }

  bool _isFlutter(InterfaceElement cls) {
    final uri = cls.enclosingElement.uri;
    return uri.scheme == 'package' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'flutter';
  }
}

class _ConstructsProbe extends RecursiveAstVisitor<void> {
  _ConstructsProbe(this.keys);

  final Set<String> keys;
  bool found = false;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final cls = node.constructorName.element?.enclosingElement;
    if (cls != null && keys.contains(WrapperSemantics._key(cls))) found = true;
    super.visitInstanceCreationExpression(node);
  }
}

class _FallbackProbe extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    found = true;
    super.visitConditionalExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.lexeme == '??') found = true;
    super.visitBinaryExpression(node);
  }
}

/// Collects the names of the owner's fields read inside an expression,
/// either bare (`label`) or via `widget.label` / `this.label`.
class _FieldRefs extends RecursiveAstVisitor<void> {
  _FieldRefs(this.fields, {this.accounted = const {}});

  final Set<String> fields;

  /// Sink expressions already judged; fields inside them are skipped.
  final Set<AstNode> accounted;
  final Set<String> refs = {};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!fields.contains(node.name)) return;
    for (AstNode? n = node; n != null; n = n.parent) {
      if (accounted.contains(n)) return;
    }
    final element = node.element;
    if (element is LocalVariableElement || element is FormalParameterElement) {
      return;
    }
    final parent = node.parent;
    if (parent is PrefixedIdentifier && parent.identifier == node) {
      final prefix = parent.prefix.name;
      if (prefix != 'widget') return;
    } else if (parent is PropertyAccess && parent.propertyName == node) {
      final target = parent.target;
      final ok =
          target is ThisExpression ||
          (target is SimpleIdentifier && target.name == 'widget');
      if (!ok) return;
    }
    refs.add(node.name);
  }
}
