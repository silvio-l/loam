import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'public_api_collector.dart';
import 'rule.dart';
import 'usage_index.dart';

/// Detects public top-level symbols in `lib/` that are never referenced
/// anywhere in the project.
///
/// Rule ID: `unused-public-exports`
///
/// This is Slice A (Top-Level): only top-level declarations are checked.
/// Member-level analysis is Slice B (future sprint).
///
/// The rule implements the [Rule] interface unchanged — no pipeline modification
/// is needed (Invariant 4). It is deterministic: identical inputs produce
/// identical outputs in identical order (Invariant 5).
///
/// Conservative defaults (in doubt → do NOT report):
/// - Private symbols, entrypoints (`main`), generated files, re-exported
///   symbols, `@visibleForTesting`/`@pragma` annotations are excluded by
///   [PublicApiCollector].
/// - The rule does NOT crash when [ProjectLoadResult.errors] is non-empty;
///   it analyses the resolvable files only.
///
/// **Publishable-package mode** (`StackProfile.isPublishable == true`):
///
/// On a publishable package (no `publish_to: none`), any file directly under
/// `lib/` (but not under `lib/src/`) is importable by external consumers as
/// `package:mypackage/foo.dart`. Symbols declared in those files are part of
/// the *deliberately-public* API and must not be reported as unused — they may
/// be consumed by packages that the current analysis cannot see.
///
/// Symbols in `lib/src/` remain eligible for reporting on publishable packages
/// because `lib/src/` is the Dart convention for internal implementation
/// details that are not part of the publicly advertised API.
///
/// On an app (`publish_to: none`, `isPublishable == false`) the behaviour is
/// identical to before this change — all unreferenced public symbols in `lib/`
/// are reported.
class UnusedPublicExportsRule implements Rule {
  /// Creates an [UnusedPublicExportsRule] rooted at [projectRoot].
  const UnusedPublicExportsRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  ///
  /// Used to compute POSIX-relative paths for fingerprints and [Finding.filePath].
  final String projectRoot;

  @override
  String get ruleId => 'unused-public-exports';

  @override
  List<Finding> run(ProjectLoadResult result) {
    // Read publishability from the stack profile — do NOT re-parse pubspec.
    // StackProfile is populated by ProjectLoader and carried on ProjectLoadResult.
    final isPublishable = result.stackProfile.isPublishable;

    // Build the project-wide reference index from all resolved files.
    final index = UsageIndex.build(result);

    // Collect public top-level candidates from lib/ files.
    final collector = const PublicApiCollector();
    final candidates = collector.collect(result, projectRoot);

    // Compute the difference: candidates not referenced anywhere.
    final findings = <Finding>[];

    for (final candidate in candidates) {
      if (index.isReferenced(candidate.element)) continue;

      // Publishable-package suppression: symbols directly in lib/ (not lib/src/)
      // are part of the intentional public API on a publishable package.
      // External consumers can import them by path — suppress to avoid FP.
      if (isPublishable && _isTopLevelLibPath(candidate.relativePath)) continue;

      final fingerprint = computeFingerprint(
        ruleId: ruleId,
        relativePath: candidate.relativePath,
        semanticAnchor: candidate.semanticAnchor,
      );

      findings.add(
        Finding(
          ruleId: ruleId,
          severity: Severity.warning,
          filePath: candidate.relativePath,
          line: candidate.line,
          message: 'unused public ${candidate.kind} `${candidate.name}`',
          fingerprint: fingerprint,
          kind: 'unused-public-export',
          remedy:
              'No reference to `${candidate.name}` exists anywhere in this '
              'package. Make it private (prefix with `_`) or delete it. If it '
              "is intentionally part of a published package's public API, that "
              'is the one legitimate exception — keep it and suppress with '
              '`// loam-ignore: unused-public-exports`, but only after '
              'confirming an external consumer actually imports it.',
        ),
      );
    }

    // Deterministic sort: by relativePath, then by symbol name (semanticAnchor).
    // This satisfies Invariant 5 (reproducibility across runs).
    findings.sort((a, b) {
      final pathCmp = a.filePath.compareTo(b.filePath);
      if (pathCmp != 0) return pathCmp;
      return a.message.compareTo(b.message);
    });

    return findings;
  }

  /// Returns `true` when [relativePath] is directly under `lib/` but NOT under
  /// `lib/src/`.
  ///
  /// Files directly under `lib/` (e.g. `lib/api.dart`, `lib/feature/page.dart`)
  /// are importable by external consumers as `package:mypkg/api.dart`. Symbols
  /// declared there are part of the intentional public API on a publishable
  /// package and must not be flagged as unused.
  ///
  /// `lib/src/` is the Dart convention for internal implementation details; it
  /// is not suppressed here so that internally-dead symbols in `lib/src/` that
  /// are not re-exported continue to surface as findings.
  static bool _isTopLevelLibPath(String relativePath) {
    return relativePath.startsWith('lib/') &&
        !relativePath.startsWith('lib/src/');
  }
}
