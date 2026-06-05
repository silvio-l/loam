import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../loader/project_loader.dart';

/// Builds a project-wide reference graph from a [ProjectLoadResult].
///
/// Traverses ALL resolved units (lib/, bin/, test/, tool/) via an AST visitor
/// and records every [Element] that is referenced outside its own declaration
/// name token.
///
/// "Declaration name" means: the identifier that IS the name of a top-level
/// [Declaration] node in the same compilation unit. This is detected by
/// checking whether the [SimpleIdentifier] node is the direct name token of an
/// enclosing [Declaration] node — using AST parent-child relationships, not
/// offset comparisons (which are file-local and can alias across files).
///
/// This isolates analyzer-v13 specifics (Element/Fragment split,
/// `SimpleIdentifier.element` instead of `staticElement`) from the rule layer.
class UsageIndex {
  UsageIndex._(this._referenced);

  /// Builds the index from [loadResult].
  ///
  /// Processes all files in [ProjectLoadResult.resolved] AND all part-file
  /// compilation units in [ProjectLoadResult.partUnits]. Files in
  /// [ProjectLoadResult.errors] are silently skipped (the rule must not crash
  /// on partial load results).
  ///
  /// Part files must also be scanned for references: a symbol referenced only
  /// from a part file would otherwise appear unreferenced and be incorrectly
  /// reported as unused (HellerIO FP #2 pattern — symbol accessed via
  /// `ClassName.field` inside a `part of` file).
  factory UsageIndex.build(ProjectLoadResult loadResult) {
    final referenced = <int>{}; // canonical element ids

    for (final file in loadResult.resolved) {
      // Collect the set of element ids for which the name identifier lives in
      // this compilation unit. These are excluded from "referenced" when
      // encountered at the exact declaration name position.
      final declaredIds = _collectDeclaredIds(file.result.unit);

      final visitor = _ReferenceCollector(referenced, declaredIds);
      file.result.unit.accept(visitor);
    }

    // Also scan part-file compilation units for references. Part files are not
    // standalone library entries (ProjectLoader skips them for resolved[]) but
    // their AST may reference symbols declared in other libraries. Without this
    // pass, those references are invisible and their targets appear unused.
    for (final partUnit in loadResult.partUnits) {
      final declaredIds = _collectDeclaredIds(partUnit.unit);
      final visitor = _ReferenceCollector(referenced, declaredIds);
      partUnit.unit.accept(visitor);
    }

    return UsageIndex._(referenced);
  }

  /// Set of canonical element ids that are referenced outside their own
  /// declaration site.
  final Set<int> _referenced;

  /// Returns `true` if [element] is referenced somewhere outside its own
  /// declaration name identifier across the whole project.
  bool isReferenced(Element element) {
    final canonical = _canonical(element);
    return _referenced.contains(canonical.id);
  }

  /// Collects the canonical ids of all top-level elements declared in [unit],
  /// keyed to the offset of their name token. Used to exclude self-references.
  static Set<int> _collectDeclaredIds(CompilationUnit unit) {
    final ids = <int>{};
    for (final decl in unit.declarations) {
      final element = _elementOfDeclaration(decl);
      if (element != null) {
        ids.add(_canonical(element).id);
      }
      // Also collect member-level declared ids (constructors, methods, fields)
      // so their name identifiers are not counted as references.
      _collectMemberIds(decl, ids);
    }
    return ids;
  }

  static void _collectMemberIds(Declaration decl, Set<int> ids) {
    if (decl is ClassDeclaration) {
      for (final member in decl.body.members) {
        final element = _elementOfDeclaration(member);
        if (element != null) ids.add(_canonical(element).id);
      }
    }
  }

  /// Returns the primary [Element] for a [Declaration].
  static Element? _elementOfDeclaration(Declaration decl) {
    if (decl is ClassDeclaration) return decl.declaredFragment?.element;
    if (decl is MixinDeclaration) return decl.declaredFragment?.element;
    if (decl is EnumDeclaration) return decl.declaredFragment?.element;
    if (decl is ExtensionDeclaration) return decl.declaredFragment?.element;
    if (decl is FunctionDeclaration) return decl.declaredFragment?.element;
    if (decl is TypeAlias) return decl.declaredFragment?.element;
    if (decl is ConstructorDeclaration) {
      return decl.declaredFragment?.element;
    }
    if (decl is MethodDeclaration) {
      return decl.declaredFragment?.element;
    }
    if (decl is TopLevelVariableDeclaration) {
      final variables = decl.variables.variables;
      if (variables.isEmpty) return null;
      final fragment = variables.first.declaredFragment;
      if (fragment is TopLevelVariableFragment) return fragment.element;
      return null;
    }
    if (decl is VariableDeclaration) {
      final fragment = decl.declaredFragment;
      if (fragment is TopLevelVariableFragment) return fragment.element;
      if (fragment is FieldFragment) return fragment.element;
      return null;
    }
    return null;
  }

  /// Resolves getter/setter accessors to their underlying variable so that
  /// all references to the same logical symbol map to one id.
  static Element _canonical(Element element) {
    if (element is PropertyAccessorElement) {
      return element.variable;
    }
    return element;
  }
}

// ---------------------------------------------------------------------------
// AST Visitor
// ---------------------------------------------------------------------------

/// Visits every [SimpleIdentifier] in the AST and records referenced elements,
/// skipping identifiers whose canonical element id is in [_declaredInThisUnit]
/// AND that are the declaration-name of that element (i.e. the name token of
/// their own [Declaration] parent).
class _ReferenceCollector extends RecursiveAstVisitor<void> {
  _ReferenceCollector(this._referenced, this._declaredInThisUnit);

  final Set<int> _referenced;

  /// Canonical element ids declared in the current compilation unit.
  final Set<int> _declaredInThisUnit;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element != null) {
      final canonical = _UsageIndexHelper.canonical(element);
      // Only exclude if: element is declared in this unit AND this node is the
      // actual name of that declaration (checked via AST parent relationship).
      final isDeclaredHere = _declaredInThisUnit.contains(canonical.id);
      if (!isDeclaredHere || !_isDeclarationNameNode(node)) {
        _referenced.add(canonical.id);
      }
    }
    super.visitSimpleIdentifier(node);
  }

  /// Handles type annotations: `UsedClass _field = UsedClass()` — the type
  /// annotation `UsedClass` appears as a [NamedType] node, not a
  /// [SimpleIdentifier]. We record its element as a reference.
  @override
  void visitNamedType(NamedType node) {
    final element = node.element;
    if (element != null) {
      final canonical = _UsageIndexHelper.canonical(element);
      _referenced.add(canonical.id);
    }
    super.visitNamedType(node);
  }

  /// Returns `true` when [node] is the name identifier that directly belongs
  /// to a [Declaration] node — i.e., the point of declaration, not a usage.
  ///
  /// Uses AST parent traversal. Works for all declaration types in Dart:
  /// classes, functions, variables, constructors, methods, etc.
  static bool _isDeclarationNameNode(SimpleIdentifier node) {
    final parent = node.parent;

    // FunctionDeclaration, MethodDeclaration, ConstructorDeclaration,
    // EnumDeclaration, ExtensionDeclaration, MixinDeclaration, TypeAlias
    // all expose a `name` Token.
    if (parent is FunctionDeclaration && parent.name == node.token) return true;
    if (parent is MethodDeclaration && parent.name == node.token) return true;
    if (parent is ConstructorDeclaration && parent.name == node.token) {
      return true;
    }
    if (parent is ExtensionDeclaration && parent.name == node.token) {
      return true;
    }
    if (parent is MixinDeclaration && parent.name == node.token) return true;
    if (parent is TypeAlias && parent.name == node.token) return true;
    if (parent is VariableDeclaration && parent.name == node.token) return true;

    // In analyzer v13, ClassDeclaration and EnumDeclaration expose the name
    // via namePart → NameWithTypeParameters → typeName (a Token).
    if (parent is NameWithTypeParameters && parent.typeName == node.token) {
      return true;
    }

    return false;
  }
}

/// Exposes [UsageIndex._canonical] to the visitor without making it public API.
abstract class _UsageIndexHelper {
  static Element canonical(Element element) => UsageIndex._canonical(element);
}
