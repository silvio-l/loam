import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects `// ignore:` and `// ignore_for_file:` directives that suppress an
/// analyzer diagnostic without providing a justification (AI-slop, CONTEXT.md).
///
/// Rule ID: `slop-unjustified-ignore`
///
/// A finding is emitted for each `// ignore:` or `// ignore_for_file:` comment
/// that carries **no** accompanying rationale. A rationale is considered present
/// when either of the following conditions holds:
///
/// 1. **Inline reason** — there is non-whitespace text in the same comment line
///    after the lint-name list:
///    `// ignore: lint_name – because the generated stub always triggers this`
/// 2. **Line-above comment** — the line immediately preceding the directive is
///    itself a `//` comment line (no blank line between):
///    ```dart
///    // The generated stub always triggers avoid_print — keep suppressed.
///    // ignore: avoid_print
///    ```
///
/// What this rule deliberately does **NOT** catch:
/// - Directives in generated files (`*.g.dart`, `*.freezed.dart`, etc.) —
///   excluded via [isGeneratedDartFile] at the start of each file loop.
/// - `/// doc-comment` lines — these are not `// ignore:` directives.
/// - Multi-lint ignores where any lint name is accompanied by a trailing reason
///   (already covered by condition 1 above).
/// - `// ignore:` text inside string literals — conservative: the raw comment
///   scan cannot distinguish in-string from real directives without full parsing,
///   but this false-positive case is practically non-existent and acceptable.
///
/// **Semantic anchor (fingerprint stability):**
/// `directiveKind:normalizedLintNames:occurrenceIndex` — where `directiveKind`
/// is `ignore` or `ignore_for_file`, `normalizedLintNames` is the sorted,
/// comma-joined lint names, and `occurrenceIndex` counts prior occurrences of
/// the same `(kind, lints)` pair within the same file. A pure line shift (adding
/// blank lines or moving the directive without changing order) leaves the anchor
/// unchanged (Invariant 5 / fingerprint semantics).
///
/// **Finding contract:**
/// - `severity`: [Severity.info]
/// - `kind`: `'unjustified-ignore'`
/// - `remedy`: imperative fix instruction
/// - `wcagRef`: null (slop rule — no WCAG reference)
///
/// **Suppression:**
/// `// loam-ignore: slop-unjustified-ignore – <reason>` on or before the line
/// of the offending directive suppresses the finding.
class SlopUnjustifiedIgnoreRule implements Rule {
  /// The stable rule ID for [SlopUnjustifiedIgnoreRule].
  ///
  /// Exposed as a static constant so callers can filter findings by rule ID
  /// without instantiating the rule or risking a typo.
  static const String ruleIdStatic = 'slop-unjustified-ignore';

  /// Creates a [SlopUnjustifiedIgnoreRule] rooted at [projectRoot].
  ///
  /// [projectRoot] is the absolute path of the analysed package.
  const SlopUnjustifiedIgnoreRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => 'slop-unjustified-ignore';

  @override
  RuleCategory get category => RuleCategory.slop;

  @override
  List<Finding> run(ProjectLoadResult result) {
    final findings = <Finding>[];

    for (final file in result.resolved) {
      // Skip generated files — *.g.dart, *.freezed.dart, *.mocks.dart, gen-l10n.
      if (isGeneratedDartFile(file.path)) continue;

      final relativePath = p.relative(file.path, from: projectRoot);
      _scanFile(file.result.content, relativePath, findings);
    }

    return findings;
  }

  // Regex: matches `// ignore:` or `// ignore_for_file:` anywhere in a line.
  // Group 1: 'ignore' or 'ignore_for_file'
  // Group 2: everything after the colon (may be empty)
  static final RegExp _directiveRegex = RegExp(
    r'//\s*(ignore(?:_for_file)?)\s*:(.*)',
  );

  // Regex: matches a lint-name list at the start of a string.
  // Lint names: [a-z][a-z0-9_]*, comma-separated with optional whitespace.
  static final RegExp _lintNamesRegex = RegExp(
    r'^[a-z][a-z0-9_]*(?:\s*,\s*[a-z][a-z0-9_]*)*',
    caseSensitive: false,
  );

  void _scanFile(String content, String relativePath, List<Finding> findings) {
    final lines = content.split('\n');

    // Occurrence counter for stable fingerprints:
    // maps 'directiveKind:normalizedLints' → how many times seen so far.
    final occurrenceCount = <String, int>{};

    for (var i = 0; i < lines.length; i++) {
      final lineText = lines[i];

      final match = _directiveRegex.firstMatch(lineText);
      if (match == null) continue;

      final directiveKind = match.group(1)!; // 'ignore' or 'ignore_for_file'
      final afterColon = match.group(2)!; // everything after the colon

      // Condition 1: inline justification (text after lint names in the same line).
      if (_hasInlineJustification(afterColon)) continue;

      // Condition 2: justification on the immediately preceding line.
      if (i > 0 && _isCommentLine(lines[i - 1])) continue;

      // Neither condition met — emit a Finding.
      final lineNumber = i + 1; // 1-based
      final col = lineText.indexOf('//') + 1; // 1-based

      final normalizedLints = _normalizeLintNames(afterColon);
      final anchorKey = '$directiveKind:$normalizedLints';
      final idx = occurrenceCount[anchorKey] ?? 0;
      occurrenceCount[anchorKey] = idx + 1;

      final fingerprint = computeFingerprint(
        ruleId: ruleId,
        relativePath: relativePath,
        semanticAnchor: '$anchorKey:$idx',
      );

      findings.add(
        Finding(
          ruleId: ruleId,
          severity: Severity.info,
          filePath: relativePath,
          line: lineNumber,
          column: col,
          message: _buildMessage(directiveKind),
          fingerprint: fingerprint,
          kind: 'unjustified-ignore',
          remedy:
              'Add a brief explanation after the lint name(s) — '
              'e.g. `// ignore: <lint> – <reason this specific instance is safe>`. '
              'If no justification can be given, remove the directive and fix '
              'the underlying issue instead.',
        ),
      );
    }
  }

  /// Returns `true` when [afterColon] (the text after `// ignore:`) contains
  /// explanatory text beyond the lint-name list.
  ///
  /// `// ignore: lint_name` → `afterColon = ' lint_name'` → false (no extra text).
  /// `// ignore: lint_name – reason` → true (non-whitespace after lint names).
  static bool _hasInlineJustification(String afterColon) {
    final trimmed = afterColon.trim();
    if (trimmed.isEmpty) return false;

    final lintMatch = _lintNamesRegex.firstMatch(trimmed);
    if (lintMatch == null) {
      // Doesn't start with a recognised lint name — treat any remaining text
      // as potential justification (conservative: avoid false positives).
      return trimmed.isNotEmpty;
    }

    final remainder = trimmed.substring(lintMatch.end).trim();
    return remainder.isNotEmpty;
  }

  /// Returns `true` when [line] is a `//` comment (possibly with leading
  /// whitespace). Used to detect justification on the preceding line.
  static bool _isCommentLine(String line) {
    return line.trimLeft().startsWith('//');
  }

  /// Extracts the lint names from [afterColon], sorts them and joins with ','
  /// for a position-stable fingerprint anchor.
  static String _normalizeLintNames(String afterColon) {
    final trimmed = afterColon.trim();
    final lintMatch = _lintNamesRegex.firstMatch(trimmed);
    if (lintMatch == null) return '';
    final lintStr = lintMatch.group(0)!;
    final lints =
        lintStr
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
          ..sort();
    return lints.join(',');
  }

  static String _buildMessage(String directiveKind) {
    if (directiveKind == 'ignore_for_file') {
      return '`// ignore_for_file:` suppresses an analyzer diagnostic '
          'for this entire file without justification — '
          'add a brief explanation or remove the directive and fix the '
          'underlying issue.';
    }
    return '`// ignore:` suppresses an analyzer diagnostic without '
        'justification — '
        'add a brief explanation or remove the directive and fix the '
        'underlying issue.';
  }
}
