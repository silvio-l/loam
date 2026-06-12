import 'package:analyzer/dart/element/element.dart';

/// Classification result returned by [CodegenInputClassifier.classify].
///
/// [isCodegenInput] is `true` when the class is identified as an input to a
/// code generator and its public members should therefore not be reported as
/// unused (they are consumed by the generated code at build time, not via
/// static element references).
///
/// [reason] identifies *which* rule matched, intended for diagnostics /
/// dogfooding — it is never surfaced in a [Finding] directly.
class CodegenInputClassification {
  /// Creates a [CodegenInputClassification].
  const CodegenInputClassification({
    required this.isCodegenInput,
    required this.reason,
  });

  /// `true` when the class is identified as a code-gen input.
  final bool isCodegenInput;

  /// Short identifier for the matched rule.
  ///
  /// - `'base_type:<name>'` — matched via the base-type registry
  ///   (e.g. `'base_type:Table'`).
  /// - `'annotation:<name>'` — matched via the annotation registry
  ///   (e.g. `'annotation:freezed'`).
  /// - `'fallback:part_generated'` — matched via the structural part-file
  ///   heuristic (library declares `part '*.g.dart'` or `'*.freezed.dart'`).
  /// - `'none'` — not a code-gen input.
  final String reason;

  /// A classification that means "not a code-gen input".
  static const none = CodegenInputClassification(
    isCodegenInput: false,
    reason: 'none',
  );
}

/// Classifies a class / interface element as a code-gen input.
///
/// A class is a code-gen input when a code generator (e.g. Drift build_runner,
/// freezed, json_serializable, Riverpod) reads its public members at build time
/// to produce a companion `*.g.dart` / `*.freezed.dart` file. In that case the
/// members are "used" by the generator — but the element model will not see any
/// static reference to them, causing false positives in the
/// `unused-public-exports` rule.
///
/// ## Classification order (first match wins)
///
/// 1. **Base-type registry** — the class (or one of its supertypes) is in the
///    known Drift base-type set (`Table`, `DataClass`, `View`).  Checked via the
///    *element model* (supertypes), never via string matching on source text
///    (Invariant 1 — semantics over syntax).
/// 2. **Annotation registry** — the class carries one of the known code-gen
///    annotations (`@DriftDatabase`, `@DataClassName`, `@riverpod`, `@Riverpod`,
///    `@freezed`, `@JsonSerializable`).
/// 3. **Structural fallback** — the library declares a `part '*.g.dart'` or
///    `part '*.freezed.dart'` directive AND the class itself binds a generated
///    `_$`-counterpart (`extends _$X` / `with _$X`). The part directive alone is
///    deliberately not enough: plain hand-written classes colocated with a
///    generated notifier must stay candidates (no over-suppression).
///
/// The `reason` field of [CodegenInputClassification] identifies which path
/// matched, enabling diagnostics in dogfooding without altering [Finding] output.
class CodegenInputClassifier {
  /// Creates a [CodegenInputClassifier].
  const CodegenInputClassifier();

  // ---------------------------------------------------------------------------
  // Known base-type registry (Drift component supertypes)
  // ---------------------------------------------------------------------------

  /// Unqualified names of Drift base types whose subclasses are code-gen inputs.
  ///
  /// Checked against `InterfaceElement.allSupertypes` names; the package origin
  /// is intentionally *not* checked because the fixture classes in tests are
  /// plain subclasses without the real Drift package imported.  In production
  /// code the element model resolves the correct type — no two unrelated
  /// packages are expected to expose a class named `Table` that users extend.
  static const Set<String> _baseTypeRegistry = {'Table', 'DataClass', 'View'};

  // ---------------------------------------------------------------------------
  // Known annotation registry
  // ---------------------------------------------------------------------------

  /// Unqualified annotation class names that mark a class as a code-gen input.
  static const Set<String> _annotationRegistry = {
    'DriftDatabase',
    'DataClassName',
    'riverpod',
    'Riverpod',
    'freezed',
    'JsonSerializable',
    'injectable',
    'module',
    'RoutePage',
    'GenerateMocks',
    'Collection',
    'Entity',
    'HiveType',
  };

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Classifies [classElement] as a code-gen input or not.
  ///
  /// [classElement] must be an [InterfaceElement] (class, mixin, or enum);
  /// passing any other element type always returns
  /// [CodegenInputClassification.none].
  CodegenInputClassification classify(Element classElement) {
    if (classElement is! InterfaceElement) {
      return CodegenInputClassification.none;
    }

    // --- 1. Base-type registry (supertype chain) ---
    final baseTypeMatch = _checkBaseTypes(classElement);
    if (baseTypeMatch != null) {
      return CodegenInputClassification(
        isCodegenInput: true,
        reason: 'base_type:$baseTypeMatch',
      );
    }

    // --- 2. Annotation registry ---
    final annotationMatch = _checkAnnotations(classElement);
    if (annotationMatch != null) {
      return CodegenInputClassification(
        isCodegenInput: true,
        reason: 'annotation:$annotationMatch',
      );
    }

    // --- 3. Structural fallback: part '*.g.dart' / '*.freezed.dart' ---
    // NARROWED: a generated part directive at library level is necessary but
    // NOT sufficient. Riverpod/freezed colocate hand-written plain classes in
    // the same library as a generated counterpart, so a library-wide rule would
    // over-suppress those plain classes (false negatives — observed on Hellerio,
    // e.g. `PremiumEntitlement` next to a `@riverpod` notifier). The class must
    // ALSO bind its generated counterpart (`extends _$X` / `with _$X`).
    if (_hasGeneratedPartDirective(classElement) &&
        _bindsGeneratedSupertype(classElement)) {
      return const CodegenInputClassification(
        isCodegenInput: true,
        reason: 'fallback:part_generated',
      );
    }

    return CodegenInputClassification.none;
  }

  // ---------------------------------------------------------------------------
  // Path 1 — Base-type registry
  // ---------------------------------------------------------------------------

  /// Returns the matched base-type name if [element] (or any supertype in the
  /// chain) is in [_baseTypeRegistry]; `null` otherwise.
  String? _checkBaseTypes(InterfaceElement element) {
    for (final supertype in element.allSupertypes) {
      final name = supertype.element.name;
      if (_baseTypeRegistry.contains(name)) return name;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Path 2 — Annotation registry
  // ---------------------------------------------------------------------------

  /// Returns the matched annotation name if [element] carries one of the known
  /// code-gen annotations; `null` otherwise.
  String? _checkAnnotations(InterfaceElement element) {
    for (final annotation in element.metadata.annotations) {
      final annotationElement = annotation.element;
      // Constructor annotations: @freezed, @JsonSerializable(), etc.
      if (annotationElement is ConstructorElement) {
        final name = annotationElement.enclosingElement.name;
        if (name != null && _annotationRegistry.contains(name)) return name;
      }
      // Property/field annotations: @riverpod (lowercase constant).
      if (annotationElement is PropertyAccessorElement) {
        final name = annotationElement.variable.name;
        if (_annotationRegistry.contains(name)) return name;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Path 3 — Structural fallback
  // ---------------------------------------------------------------------------

  /// Returns `true` if the library that owns [element] declares a `part`
  /// directive whose URI ends with `.g.dart` or `.freezed.dart`.
  ///
  /// This is checked on the *primary* library fragment (index 0) only.  If the
  /// library has multiple fragments (augmentations), the part directives should
  /// be in the root fragment.
  bool _hasGeneratedPartDirective(InterfaceElement element) {
    // element.library is always non-null for InterfaceElement — it is declared
    // in a library context by definition.
    final library = element.library;

    for (final fragment in library.fragments) {
      for (final part in fragment.partIncludes) {
        final uri = part.uri;
        if (uri is DirectiveUriWithRelativeUriString) {
          final uriString = uri.relativeUriString;
          if (uriString.endsWith('.g.dart') ||
              uriString.endsWith('.freezed.dart') ||
              uriString.endsWith('.gr.dart') ||
              uriString.endsWith('.config.dart') ||
              uriString.endsWith('.mocks.dart') ||
              uriString.endsWith('.pb.dart')) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Returns `true` if [element] binds a generated counterpart, i.e. it extends
  /// or mixes in a supertype whose unqualified name starts with `_$`.
  ///
  /// This is the convention used by freezed (`class X with _$X`) and Riverpod
  /// class-based notifiers (`class X extends _$X`): the generated `_$X` symbol
  /// lives in the companion part file. Plain hand-written classes that merely
  /// cohabit a part-bearing library carry no such binding and must stay
  /// candidates (Invariant 1 — the check is over the element supertype chain,
  /// not source text).
  bool _bindsGeneratedSupertype(InterfaceElement element) {
    for (final supertype in element.allSupertypes) {
      final name = supertype.element.name;
      if (name != null && name.startsWith(r'_$')) return true;
    }
    return false;
  }
}
