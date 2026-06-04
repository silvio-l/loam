import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';

/// A candidate public top-level symbol for the `unused-public-exports` rule.
class PublicApiCandidate {
  const PublicApiCandidate({
    required this.element,
    required this.relativePath,
    required this.kind,
    required this.line,
    String? semanticAnchor,
  }) : _semanticAnchor = semanticAnchor;

  /// The resolved element for this symbol.
  final Element element;

  /// POSIX path relative to the project root.
  final String relativePath;

  /// Human-readable kind label (e.g. `class`, `function`, `method`).
  final String kind;

  /// 1-based line number of the declaration.
  final int line;

  /// The unqualified name of the symbol.
  String get name => element.name ?? '<unknown>';

  /// Stable semantic key used for fingerprinting.
  ///
  /// For top-level symbols this is the unqualified name (same as [name]).
  /// For member symbols this is the qualified name (`ClassName.memberName`)
  /// so that fingerprints survive class renames without colliding.
  String get semanticAnchor => _semanticAnchor ?? name;

  final String? _semanticAnchor;
}

/// Collects public top-level declarations under `lib/` as candidates for the
/// `unused-public-exports` rule (Slice A — Top-Level only).
///
/// Conservative exclusions applied:
/// - Private symbols (name starts with `_`).
/// - Generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`).
/// - `main` functions (entrypoints must never be reported as unused).
/// - Symbols annotated with `@visibleForTesting` or `@pragma`.
/// - Symbols in libraries that re-export them via `export` directives
///   (re-exported symbols are part of the public API).
///
/// **Part-file handling:** The [ProjectLoader] skips `part` files as
/// standalone resolved entries (they are not libraries). This collector
/// therefore traverses `libraryElement.fragments` for every resolved library
/// file, which covers declarations in the library file itself (fragment 0)
/// as well as declarations in each `part` file (fragment 1+). Deduplication
/// is based on element identity (`element.id`), so each symbol yields
/// exactly one candidate regardless of how many fragments the library has.
class PublicApiCollector {
  const PublicApiCollector();

  /// Collects all public top-level candidates from `lib/` files in [result].
  ///
  /// [projectRoot] is the absolute path of the analysed package root. It is
  /// used to compute [PublicApiCandidate.relativePath].
  List<PublicApiCandidate> collect(
    ProjectLoadResult result,
    String projectRoot,
  ) {
    final candidates = <PublicApiCandidate>[];

    // Deduplicate by element id: an element can only appear in one fragment,
    // but defensive guard prevents any accidental double-visits.
    final seenIds = <int>{};

    // Build the set of element ids that are re-exported anywhere in the project.
    final reExported = _collectReExportedElements(result);

    for (final file in result.resolved) {
      if (!file.isUnderLib) continue;

      final library = file.result.libraryElement;

      // Walk every fragment of the library (fragment 0 = the library file
      // itself; fragment 1+ = part files). This ensures that declarations in
      // part files are collected even though part files do not appear as
      // standalone entries in ProjectLoadResult.resolved.
      for (final fragment in library.fragments) {
        final fragmentPath = fragment.source.fullName;

        // Skip generated part files (e.g. *.g.dart included via `part`).
        if (_isGeneratedFile(fragmentPath)) continue;

        final relPath = _toRelativePosix(fragmentPath, projectRoot);
        final lineInfo = fragment.lineInfo;

        // Collect each declaration kind from this fragment.
        _visitFragmentDeclarations(
          fragment: fragment,
          relPath: relPath,
          lineInfo: lineInfo,
          reExported: reExported,
          seenIds: seenIds,
          candidates: candidates,
        );
      }
    }

    return candidates;
  }

  // ---------------------------------------------------------------------------
  // Fragment traversal
  // ---------------------------------------------------------------------------

  void _visitFragmentDeclarations({
    required LibraryFragment fragment,
    required String relPath,
    required LineInfo lineInfo,
    required Set<int> reExported,
    required Set<int> seenIds,
    required List<PublicApiCandidate> candidates,
  }) {
    // Classes (including ClassDeclaration and ClassTypeAlias)
    for (final f in fragment.classes) {
      _addIfEligible(
        element: f.element,
        kind: 'class',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
      // Skip member collection for re-exported, generated, or excluded classes:
      // if the enclosing class is excluded from top-level candidates, its
      // members carry the same exclusion reason.
      if (_isMemberEligibleEnclosingType(f.element, reExported)) {
        _visitInstanceMemberFragments(
          instanceFragment: f,
          enclosingName: f.element.name ?? '',
          relPath: relPath,
          lineInfo: lineInfo,
          seenIds: seenIds,
          candidates: candidates,
        );
      }
    }

    // Enums
    for (final f in fragment.enums) {
      _addIfEligible(
        element: f.element,
        kind: 'enum',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
      if (_isMemberEligibleEnclosingType(f.element, reExported)) {
        _visitInstanceMemberFragments(
          instanceFragment: f,
          enclosingName: f.element.name ?? '',
          relPath: relPath,
          lineInfo: lineInfo,
          seenIds: seenIds,
          candidates: candidates,
        );
      }
    }

    // Mixins
    for (final f in fragment.mixins) {
      _addIfEligible(
        element: f.element,
        kind: 'mixin',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
      if (_isMemberEligibleEnclosingType(f.element, reExported)) {
        _visitInstanceMemberFragments(
          instanceFragment: f,
          enclosingName: f.element.name ?? '',
          relPath: relPath,
          lineInfo: lineInfo,
          seenIds: seenIds,
          candidates: candidates,
        );
      }
    }

    // Extensions
    for (final f in fragment.extensions) {
      _addIfEligible(
        element: f.element,
        kind: 'extension',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
      if (_isMemberEligibleEnclosingType(f.element, reExported)) {
        _visitInstanceMemberFragments(
          instanceFragment: f,
          enclosingName: f.element.name ?? '',
          relPath: relPath,
          lineInfo: lineInfo,
          seenIds: seenIds,
          candidates: candidates,
        );
      }
    }

    // Top-level functions
    for (final f in fragment.functions) {
      _addIfEligible(
        element: f.element,
        kind: 'function',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Typedefs (type aliases)
    for (final f in fragment.typeAliases) {
      _addIfEligible(
        element: f.element,
        kind: 'typedef',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Top-level variables: only explicit declarations (const/var/final x = …),
    // NOT the synthetic backing variable for an explicit getter/setter pair.
    for (final f in fragment.topLevelVariables) {
      if (!f.element.isOriginDeclaration) continue;
      _addIfEligible(
        element: f.element,
        kind: 'variable',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Explicit top-level getters (`int get foo => …`).
    // We use the underlying PropertyInducingElement (variable) as the
    // canonical element to match UsageIndex._canonical.
    for (final f in fragment.getters) {
      // Only explicit getter declarations — skip synthetic getters
      // auto-generated for variable declarations.
      if (!f.element.isOriginDeclaration) continue;
      final canonicalElement = f.element.variable;
      _addIfEligible(
        element: canonicalElement,
        kind: 'getter',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Explicit top-level setters (`set foo(x) {…}`).
    for (final f in fragment.setters) {
      if (!f.element.isOriginDeclaration) continue;
      final canonicalElement = f.element.variable;
      // seenIds guards against a getter+setter pair reporting the same
      // canonical variable element twice.
      _addIfEligible(
        element: canonicalElement,
        kind: 'setter',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Member traversal (Slice B)
  // ---------------------------------------------------------------------------

  /// Visits public member declarations within an [InstanceFragment] (class,
  /// enum, mixin, or extension fragment) and adds eligible member candidates.
  ///
  /// Conservative member-specific exclusions applied here (in addition to the
  /// top-level exclusions in [_addIfEligible]):
  ///
  /// - **`@override` annotation**: any member annotated with `@override` is
  ///   excluded (it already fulfils an inherited contract and is not standalone).
  /// - **Inherited contract**: for [InterfaceElement] enclosing types, members
  ///   for which [InterfaceElement.getOverridden] returns a non-null result are
  ///   excluded (they implement or override a superclass/interface/mixin member).
  /// - **Synthetic fields**: only fields whose [FieldElement.isOriginDeclaration]
  ///   is `true` are collected; enum `values`/`index` fields (identified by
  ///   [FieldElement.isOriginEnumValues] and enum constants identified by
  ///   [FieldElement.isEnumConstant]) are excluded.
  /// - **Synthetic accessor methods**: only methods with
  ///   [MethodElement.isOriginDeclaration] are collected.
  /// - **Operators**: operator methods (e.g. `==`, `[]`) are excluded
  ///   conservatively because they are often part of implicit contracts.
  /// - **Member getters/setters**: only explicit declarations
  ///   ([PropertyAccessorElement.isOriginDeclaration]) are collected; synthetic
  ///   field-induced getters/setters are excluded.
  void _visitInstanceMemberFragments({
    required InstanceFragment instanceFragment,
    required String enclosingName,
    required String relPath,
    required LineInfo lineInfo,
    required Set<int> seenIds,
    required List<PublicApiCandidate> candidates,
  }) {
    // Skip anonymous extensions (no enclosing name → no qualified anchor).
    if (enclosingName.isEmpty) return;

    final enclosingElement = instanceFragment.element;

    // Conservative: if the enclosing type itself carries a conservative
    // annotation (@visibleForTesting, @pragma) its members are transitively
    // excluded — the class is intended for special exposure and its member
    // visibility is not independently meaningful.
    if (_hasConservativeAnnotation(enclosingElement)) return;

    // Methods
    for (final mf in instanceFragment.methods) {
      final method = mf.element;
      if (!method.isOriginDeclaration) continue;
      if (method.isOperator) continue; // conservative: operators excluded
      // Abstract methods are interface contracts — never report them.
      if (method.isAbstract) {
        continue;
      }
      if (_hasMemberOverrideAnnotation(method)) continue;
      if (_isInheritedMember(enclosingElement, method.name ?? '')) continue;
      if (_hasConservativeAnnotation(method)) continue;

      final memberName = method.name ?? '';
      if (memberName.isEmpty || memberName.startsWith('_')) continue;

      if (!seenIds.add(method.id)) continue;

      final loc = lineInfo.getLocation(mf.nameOffset ?? mf.offset);
      candidates.add(
        PublicApiCandidate(
          element: method,
          relativePath: relPath,
          kind: 'method',
          line: loc.lineNumber,
          semanticAnchor: '$enclosingName.$memberName',
        ),
      );
    }

    // Fields: only explicit non-synthetic, non-enum-constant fields.
    for (final ff in instanceFragment.fields) {
      final field = ff.element;
      // Only explicit field declarations — skip induced/synthetic/enum values.
      if (!field.isOriginDeclaration) continue;
      if (field.isEnumConstant) continue;
      if (field.isOriginEnumValues) continue;
      if (_hasConservativeAnnotation(field)) continue;

      final fieldName = field.name ?? '';
      if (fieldName.isEmpty || fieldName.startsWith('_')) continue;

      if (!seenIds.add(field.id)) continue;

      final loc = lineInfo.getLocation(ff.offset);
      candidates.add(
        PublicApiCandidate(
          element: field,
          relativePath: relPath,
          kind: 'field',
          line: loc.lineNumber,
          semanticAnchor: '$enclosingName.$fieldName',
        ),
      );
    }

    // Explicit member getters (not synthetic field-induced getters).
    for (final gf in instanceFragment.getters) {
      final getter = gf.element;
      if (!getter.isOriginDeclaration) continue;
      // Abstract getters are interface contracts — never report them.
      if (getter.isAbstract) {
        continue;
      }
      if (_hasMemberOverrideAnnotation(getter)) continue;
      if (_isInheritedMember(enclosingElement, getter.name ?? '')) continue;
      if (_hasConservativeAnnotation(getter)) continue;

      final getterName = getter.variable.name ?? '';
      if (getterName.isEmpty || getterName.startsWith('_')) continue;

      // Use the canonical variable element as the key (same as UsageIndex).
      final canonicalElement = getter.variable;
      if (!seenIds.add(canonicalElement.id)) continue;

      final loc = lineInfo.getLocation(gf.offset);
      candidates.add(
        PublicApiCandidate(
          element: canonicalElement,
          relativePath: relPath,
          kind: 'getter',
          line: loc.lineNumber,
          semanticAnchor: '$enclosingName.$getterName',
        ),
      );
    }

    // Explicit member setters (not synthetic field-induced setters).
    for (final sf in instanceFragment.setters) {
      final setter = sf.element;
      if (!setter.isOriginDeclaration) continue;
      // Abstract setters are interface contracts — never report them.
      if (setter.isAbstract) {
        continue;
      }
      if (_hasMemberOverrideAnnotation(setter)) continue;
      if (_isInheritedMember(enclosingElement, setter.name ?? '')) continue;
      if (_hasConservativeAnnotation(setter)) continue;

      // Setter name in the element model ends with `=`; strip it for display.
      final rawName = setter.variable.name ?? '';
      if (rawName.isEmpty || rawName.startsWith('_')) continue;

      // Use the canonical variable element (getter+setter share the same var).
      final canonicalElement = setter.variable;
      if (!seenIds.add(canonicalElement.id)) continue;

      final loc = lineInfo.getLocation(sf.offset);
      candidates.add(
        PublicApiCandidate(
          element: canonicalElement,
          relativePath: relPath,
          kind: 'setter',
          line: loc.lineNumber,
          semanticAnchor: '$enclosingName.$rawName',
        ),
      );
    }
  }

  /// Returns `true` if the enclosing type [element] is eligible for member
  /// collection — i.e., it is not re-exported, not private, and does not carry
  /// a conservative annotation.
  ///
  /// Members of re-exported types (part of the public API by re-export), of
  /// types with `@visibleForTesting`/`@pragma`, or of private types are
  /// excluded transitively.
  static bool _isMemberEligibleEnclosingType(
    Element element,
    Set<int> reExported,
  ) {
    final name = element.name ?? '';
    if (name.isEmpty || name.startsWith('_')) return false;
    if (reExported.contains(element.id)) return false;
    if (_hasConservativeAnnotation(element)) return false;
    return true;
  }

  /// Returns `true` if [executable] carries an explicit `@override` annotation.
  static bool _hasMemberOverrideAnnotation(ExecutableElement executable) {
    for (final annotation in executable.metadata.annotations) {
      if (annotation.isOverride) return true;
    }
    return false;
  }

  /// Returns `true` when a member named [memberName] in [enclosingElement]
  /// would override (or implement) a member from a supertype.
  ///
  /// Uses [InterfaceElement.getOverridden] for interface types. Returns `false`
  /// for non-interface types (extensions) since they cannot have inherited
  /// members in the same sense.
  static bool _isInheritedMember(
    InstanceElement enclosingElement,
    String memberName,
  ) {
    if (enclosingElement is! InterfaceElement) return false;
    final name = Name(null, memberName);
    return enclosingElement.getOverridden(name) != null;
  }

  // ---------------------------------------------------------------------------
  // Eligibility check & candidate creation
  // ---------------------------------------------------------------------------

  void _addIfEligible({
    required Element element,
    required String kind,
    required int? nameOffset,
    required String relPath,
    required LineInfo lineInfo,
    required Set<int> reExported,
    required Set<int> seenIds,
    required List<PublicApiCandidate> candidates,
    String? semanticAnchor,
  }) {
    final name = element.name ?? '';
    if (name.isEmpty) return;
    if (name.startsWith('_')) return; // private
    if (name == 'main') return; // entrypoint
    if (_hasConservativeAnnotation(element)) return;
    if (reExported.contains(element.id)) return;

    // Deduplicate: use element id as canonical key.
    // This ensures a symbol shared across a getter+setter pair (or appearing
    // in multiple fragments) is added at most once.
    if (!seenIds.add(element.id)) return;

    final offset = nameOffset ?? 0;
    final loc = lineInfo.getLocation(offset);

    candidates.add(
      PublicApiCandidate(
        element: element,
        relativePath: relPath,
        kind: kind,
        line: loc.lineNumber,
        semanticAnchor: semanticAnchor,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns true for `*.g.dart`, `*.freezed.dart`, `*.mocks.dart`.
  static bool _isGeneratedFile(String path) {
    final basename = p.basename(path);
    return basename.endsWith('.g.dart') ||
        basename.endsWith('.freezed.dart') ||
        basename.endsWith('.mocks.dart');
  }

  /// Returns true when [element] carries a conservative annotation that marks
  /// intentional public exposure: `@visibleForTesting` or `@pragma`.
  ///
  /// `@pragma` is a built-in Dart core annotation used to communicate intent
  /// to the compiler/runtime (e.g. `@pragma('vm:entry-point')`). Any `@pragma`
  /// annotation signals deliberate exposure and is excluded conservatively.
  static bool _hasConservativeAnnotation(Element element) {
    for (final annotation in element.metadata.annotations) {
      if (annotation.isVisibleForTesting) return true;
      // @pragma is a dart:core constructor — detect via element type/name.
      final annotationElement = annotation.element;
      if (annotationElement is ConstructorElement &&
          annotationElement.enclosingElement.name == 'pragma' &&
          annotationElement.library.name == 'dart.core') {
        return true;
      }
    }
    return false;
  }

  /// Collects all element ids that are re-exported via `export` directives in
  /// any resolved file. A re-exported symbol is part of the public API and must
  /// not be reported as unused.
  Set<int> _collectReExportedElements(ProjectLoadResult result) {
    final ids = <int>{};
    for (final file in result.resolved) {
      final library = file.result.libraryElement;
      for (final exported in library.exportedLibraries) {
        for (final c in exported.classes) {
          ids.add(c.id);
        }
        for (final fn in exported.topLevelFunctions) {
          ids.add(fn.id);
        }
        for (final e in exported.enums) {
          ids.add(e.id);
        }
        for (final mixin in exported.mixins) {
          ids.add(mixin.id);
        }
        for (final ext in exported.extensions) {
          ids.add(ext.id);
        }
        for (final typedef in exported.typeAliases) {
          ids.add(typedef.id);
        }
        for (final v in exported.topLevelVariables) {
          ids.add(v.id);
        }
        // Use the canonical variable id (PropertyInducingElement) to match
        // the id that _addIfEligible receives via `f.element.variable`.
        // Using `g.id` (the PropertyAccessorElement id) would NOT match.
        for (final g in exported.getters) {
          ids.add(g.variable.id);
        }
        for (final s in exported.setters) {
          ids.add(s.variable.id);
        }
      }
    }
    return ids;
  }

  /// Returns a POSIX path relative to [projectRoot].
  static String _toRelativePosix(String absolutePath, String projectRoot) {
    final rel = p.relative(absolutePath, from: projectRoot);
    return rel.replaceAll(r'\', '/');
  }
}
