import 'dart:math' as math;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import '../model/project_path.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects plaintext credentials written into string literals.
///
/// Rule ID: `hardcoded-secrets`
///
/// Two independent detection paths, both on the parsed Dart AST (string
/// literals as syntax nodes, never a text scan over comments or docs):
///
/// 1. **Provider formats** — any string literal that contains a token with a
///    well-known, high-confidence shape (AWS access key id, GitHub token,
///    Stripe live secret key, Google API key, Slack token, Anthropic / OpenAI
///    key, PEM private key with a key body). Severity: [Severity.error], except
///    Google API keys (`AIza…`): Google documents Firebase/Maps keys as
///    client identifiers, so they are a [Severity.warning] whose remedy asks
///    to restrict the key.
/// 2. **Sensitive site + secret-looking value** — a literal assigned to a
///    variable, named argument, parameter default value, assignment target or map key whose *name*
///    says credential (`password`, `apiKey`, `clientSecret`, `authToken`, …)
///    and whose *value* passes the entropy heuristic (see [looksLikeSecret]).
///    Severity: [Severity.warning].
///
/// Deliberately **not** reported (conservative defaults — a finding must be
/// trustworthy):
/// - Test and fixture code (`test/`, `integration_test/`, `test_driver/`,
///   `fixtures/`, `example/`, `*_test.dart`), generated files and
///   `firebase_options.dart` (its API keys are public client identifiers).
/// - Placeholders and samples (`changeme`, `your-key-here`, `<token>`,
///   `example`, `dummy`, …), env-var names (`API_KEY`), storage-key names
///   (`'auth_token'`), short or low-entropy values.
/// - Values that are not a single literal: `String.fromEnvironment(...)`,
///   `Platform.environment[...]`, `a ?? 'fallback'`, interpolated strings.
///
/// **Masking:** the secret value never leaves the rule. Messages, remedy and
/// fingerprint contain only the site name, provider label and location, so
/// reports and `baseline.json` stay free of the credential.
///
/// **Semantic anchor (fingerprint stability):**
/// `scope:kind:label:occurrenceIndex` — `scope` is the enclosing
/// class/member, `label` the site name or provider id. Rotating the value or
/// shifting lines leaves the anchor unchanged.
///
/// **Suppression:** `// loam-ignore: hardcoded-secrets – <reason>` or the
/// `rules:` toggle in `loam.yaml`.
class HardcodedSecretsRule implements FileRule {
  /// The stable rule ID for [HardcodedSecretsRule].
  static const String ruleIdStatic = 'hardcoded-secrets';

  /// Creates a [HardcodedSecretsRule] rooted at [projectRoot].
  const HardcodedSecretsRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => ruleIdStatic;

  @override
  RuleCategory get category => RuleCategory.slop;

  @override
  List<Finding> run(ProjectLoadResult result) => runPerFile(this, result);

  @override
  List<Finding> runFile(LoadedFile file) {
    if (isGeneratedDartFile(file.path)) return const [];
    final relativePath = projectRelativePosixPath(file.path, projectRoot);
    if (isSecretScanExempt(relativePath)) return const [];
    return scanForSecrets(file.parsed.unit, relativePath: relativePath);
  }
}

/// Returns `true` for paths whose literals are test data or public client
/// identifiers rather than deployed credentials.
bool isSecretScanExempt(String relativePath) {
  final parts = p.posix.split(relativePath.replaceAll(r'\', '/'));
  const exemptDirs = {
    'test',
    'integration_test',
    'test_driver',
    'fixtures',
    'example',
    'examples',
  };
  if (parts.length > 1 &&
      parts.take(parts.length - 1).any(exemptDirs.contains)) {
    return true;
  }
  final base = parts.last;
  return base.endsWith('_test.dart') || base == 'firebase_options.dart';
}

/// Scans one parsed [unit] and returns its findings (pure, no I/O).
///
/// Exposed so the logic can be tested on plain parsed source without a
/// resolved project.
List<Finding> scanForSecrets(
  CompilationUnit unit, {
  required String relativePath,
}) {
  final findings = <Finding>[];
  unit.accept(
    _SecretVisitor(
      relativePath: relativePath,
      lineInfo: unit.lineInfo,
      findings: findings,
    ),
  );
  return findings;
}

// ---------------------------------------------------------------------------
// Provider formats
// ---------------------------------------------------------------------------

class _Provider {
  const _Provider(
    this.id,
    this.label,
    this.pattern, {
    this.publicIdentifier = false,
  });
  final String id;
  final String label;
  final RegExp pattern;

  /// Keys that Google documents as non-secret client identifiers (Firebase,
  /// Maps): reported as a warning that asks for key restrictions.
  final bool publicIdentifier;
}

final List<_Provider> _providers = [
  _Provider(
    'aws-access-key',
    'AWS access key id',
    RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
  ),
  _Provider(
    'github-token',
    'GitHub token',
    RegExp(r'\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,})'),
  ),
  _Provider(
    'stripe-live-key',
    'Stripe live secret key',
    RegExp(r'\b[rs]k_live_[A-Za-z0-9]{16,}'),
  ),
  _Provider(
    'google-api-key',
    'Google API key',
    RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b'),
    publicIdentifier: true,
  ),
  _Provider(
    'slack-token',
    'Slack token',
    RegExp(r'\bxox[abposr]-[0-9A-Za-z-]{20,}'),
  ),
  _Provider(
    'anthropic-key',
    'Anthropic API key',
    RegExp(r'\bsk-ant-[A-Za-z0-9_-]{20,}'),
  ),
  _Provider(
    'openai-key',
    'OpenAI API key',
    // A real key body mixes digits in; a long kebab-case identifier that
    // happens to start with `sk-` does not.
    RegExp(r'\bsk-(?:proj-)?(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{32,}'),
  ),
  // A bare header is a delimiter in PEM parsers, not a leak: require a key body.
  _Provider(
    'private-key',
    'PEM private key',
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----\s*[A-Za-z0-9+/]{30,}'),
  ),
];

// ---------------------------------------------------------------------------
// Heuristics
// ---------------------------------------------------------------------------

const _placeholderMarkers = [
  'changeme',
  'change-me',
  'change_me',
  'your',
  'xxxx',
  '****',
  'example',
  'placeholder',
  'dummy',
  'sample',
  'replace',
  'insert',
  'todo',
  'fixme',
  'foobar',
  'password',
  'secret',
  'token',
  'apikey',
  'api_key',
  'test',
  'demo',
  'fake',
  'mock',
  '1234',
  'abcd',
  '<',
  '>',
  '{{',
  r'$',
];

/// `true` when [value] reads as a placeholder or documentation sample.
bool isPlaceholderValue(String value) {
  final lower = value.toLowerCase();
  return _placeholderMarkers.any(lower.contains);
}

/// Shannon entropy of [value] in bits per character.
double shannonEntropy(String value) {
  if (value.isEmpty) return 0;
  final counts = <int, int>{};
  for (final unit in value.codeUnits) {
    counts[unit] = (counts[unit] ?? 0) + 1;
  }
  var entropy = 0.0;
  for (final count in counts.values) {
    final probability = count / value.length;
    entropy -= probability * (math.log(probability) / math.ln2);
  }
  return entropy;
}

final RegExp _separators = RegExp(r'[_\-.:/]');
final RegExp _wordLike = RegExp(r'^[a-z]+\d{0,2}$');
final RegExp _whitespace = RegExp(r'\s');
final RegExp _envName = RegExp(r'^[A-Z][A-Z0-9_]*$');
final RegExp _letter = RegExp(r'[A-Za-z]');
final RegExp _digit = RegExp(r'\d');

/// Entropy heuristic for a literal that sits on a credential-named site.
///
/// A value qualifies when it is at least 8 characters, has no whitespace,
/// is not a placeholder, is not a plain word list (`auth_token`,
/// `refreshKey`), and either mixes letters with digits at >= 3.0 bits/char or
/// is long (>= 20) and >= 4.0 bits/char.
bool looksLikeSecret(String value) {
  if (value.length < 8) return false;
  if (value.contains(_whitespace)) return false;
  if (isPlaceholderValue(value)) return false;
  if (_envName.hasMatch(value)) return false; // env name
  final segments = value.split(_separators);
  if (segments.length > 1 && segments.every(_wordLike.hasMatch)) return false;
  final entropy = shannonEntropy(value);
  final hasLetter = value.contains(_letter);
  final hasDigit = value.contains(_digit);
  if (hasLetter && hasDigit && entropy >= 3.0) return true;
  return value.length >= 20 && entropy >= 4.0;
}

final RegExp _wordSplit = RegExp(r'[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+');

const _strongWords = {
  'password',
  'passwd',
  'pwd',
  'passphrase',
  'secret',
  'token',
  'credential',
  'credentials',
  'apikey',
};
const _keyPrefixes = {
  'api',
  'private',
  'secret',
  'access',
  'auth',
  'signing',
  'encryption',
  'client',
};
const _nonSecretSuffixes = {
  'hint',
  'label',
  'prefix',
  'suffix',
  'header',
  'name',
  'field',
  'path',
  'url',
  'uri',
  'type',
  'endpoint',
  'regex',
  'pattern',
  'length',
  'placeholder',
  'id',
  'expiry',
  'ttl',
  'duration',
  'count',
};

/// `true` when the identifier or map key [name] says "credential".
///
/// `apiKey`, `client_secret`, `authToken`, `DB_PASSWORD` qualify; storage-key
/// or metadata names (`tokenKey`, `passwordHint`, `secretName`, `tokenUrl`)
/// do not.
bool isSensitiveName(String name) {
  final words = _wordSplit
      .allMatches(name)
      .map((m) => m.group(0)!.toLowerCase())
      .toList();
  if (words.isEmpty) return false;
  final last = words.last;
  if (last == 'key') {
    return words.length > 1 && _keyPrefixes.contains(words[words.length - 2]);
  }
  if (_nonSecretSuffixes.contains(last)) return false;
  return words.any(_strongWords.contains);
}

// ---------------------------------------------------------------------------
// Visitor
// ---------------------------------------------------------------------------

const String _secretRemedy =
    'Remove the literal, revoke and rotate the credential if it was '
    'ever committed, and read it at runtime instead '
    '(`String.fromEnvironment`, `Platform.environment`, or a secret '
    'store). If this is a public identifier, suppress with '
    '`// loam-ignore: hardcoded-secrets – <reason>`.';

const String _restrictRemedy =
    'Google documents Firebase and Maps keys as client identifiers, not '
    'secrets: restrict the key (API restrictions and app restrictions such '
    'as bundle id, package name or HTTP referrer) in the Google Cloud '
    'console. If it is a server-side key, treat it as a secret instead and '
    'read it at runtime.';

class _SecretVisitor extends RecursiveAstVisitor<void> {
  _SecretVisitor({
    required this.relativePath,
    required this.lineInfo,
    required this.findings,
  });

  final String relativePath;
  final LineInfo lineInfo;
  final List<Finding> findings;

  final Set<int> _handled = {};
  final Map<String, int> _occurrences = {};

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _checkSite(node.name.lexeme, node.initializer);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    _checkSite(node.name.lexeme, node.argumentExpression);
    super.visitNamedArgument(node);
  }

  @override
  void visitFormalParameterDefaultClause(FormalParameterDefaultClause node) {
    final parameter = node.parent;
    if (parameter is FormalParameter) {
      _checkSite(parameter.name?.lexeme, node.value);
    }
    super.visitFormalParameterDefaultClause(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (node.operator.type == TokenType.EQ) {
      _checkSite(_targetName(node.leftHandSide), node.rightHandSide);
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    final key = node.key;
    if (key is StringLiteral) _checkSite(key.stringValue, node.value);
    super.visitMapLiteralEntry(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (!_handled.contains(node.offset)) {
      final provider = _matchProvider(node.value);
      if (provider != null) _emitProvider(node, provider, null);
    }
    super.visitSimpleStringLiteral(node);
  }

  String? _targetName(Expression target) => switch (target) {
    SimpleIdentifier() => target.name,
    PrefixedIdentifier() => target.identifier.name,
    PropertyAccess() => target.propertyName.name,
    IndexExpression(index: final StringLiteral key) => key.stringValue,
    _ => null,
  };

  _Provider? _matchProvider(String value) {
    for (final provider in _providers) {
      final match = provider.pattern.firstMatch(value);
      if (match != null && !isPlaceholderValue(match.group(0)!)) {
        return provider;
      }
    }
    return null;
  }

  void _checkSite(String? name, Expression? value) {
    if (name == null || value is! StringLiteral) return;
    final text = value.stringValue;
    if (text == null) return; // interpolation: not a plain literal
    final provider = _matchProvider(text);
    if (provider != null) {
      _handled.add(value.offset);
      _emitProvider(value, provider, name);
      return;
    }
    if (!isSensitiveName(name) || !looksLikeSecret(text)) return;
    final anchorLabel = name;
    _emit(
      node: value,
      severity: Severity.warning,
      kind: 'sensitive-literal',
      anchorLabel: anchorLabel,
      message:
          '`$name` is assigned a hardcoded credential literal '
          '(value withheld).',
    );
  }

  void _emitProvider(StringLiteral node, _Provider provider, String? name) {
    _emit(
      node: node,
      severity: provider.publicIdentifier ? Severity.warning : Severity.error,
      kind: 'provider-key',
      anchorLabel: provider.id,
      message:
          'Hardcoded ${provider.label} in a string literal'
          '${name == null ? '' : ' (`$name`)'} (value withheld).',
      remedy: provider.publicIdentifier ? _restrictRemedy : null,
    );
  }

  void _emit({
    required AstNode node,
    required Severity severity,
    required String kind,
    required String anchorLabel,
    required String message,
    String? remedy,
  }) {
    final scope = _scopeName(node);
    final counterKey = '$scope:$kind:$anchorLabel';
    final idx = _occurrences[counterKey] ?? 0;
    _occurrences[counterKey] = idx + 1;
    final location = lineInfo.getLocation(node.offset);
    findings.add(
      Finding(
        ruleId: HardcodedSecretsRule.ruleIdStatic,
        severity: severity,
        filePath: relativePath,
        line: location.lineNumber,
        column: location.columnNumber,
        message: message,
        fingerprint: computeFingerprint(
          ruleId: HardcodedSecretsRule.ruleIdStatic,
          relativePath: relativePath,
          semanticAnchor: '$counterKey:$idx',
        ),
        kind: kind,
        remedy: remedy ?? _secretRemedy,
      ),
    );
  }

  String _scopeName(AstNode node) {
    final parts = <String>[];
    for (AstNode? c = node.parent; c != null; c = c.parent) {
      switch (c) {
        case MethodDeclaration():
          parts.add(c.name.lexeme);
        case FunctionDeclaration():
          parts.add(c.name.lexeme);
        case ConstructorDeclaration():
          parts.add(c.name?.lexeme ?? 'new');
        case ClassDeclaration():
          parts.add(c.namePart.typeName.lexeme);
        default:
      }
    }
    return parts.isEmpty ? '<top>' : parts.reversed.join('.');
  }
}
