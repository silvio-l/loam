import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/rules/hardcoded_secrets_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:test/test.dart';

// Credential-shaped test values are assembled at runtime so no complete
// token appears in this file (repo secret scan, and no real key ever lands here).
String _j(List<String> parts) => parts.join();

List<Finding> _scan(String source, {String path = 'lib/a.dart'}) =>
    scanForSecrets(parseString(content: source).unit, relativePath: path);

void main() {
  group('sensitive site + secret-looking value', () {
    test('flags variable, named argument, assignment and map key', () {
      final findings = _scan('''
const apiKey = 'k8Jx92LmQp4Zr7Tv';
void f(Client c, Cfg cfg) {
  c.connect(password: 'Tr0ub4dor&3xQ');
  cfg.clientSecret = 'q7W3eR9tY2uI5oP1';
  final m = {'auth_token': 'a9F3k2L8m4N7p1Q5'};
}
''');
      expect(findings, hasLength(4));
      expect(findings.every((f) => f.kind == 'sensitive-literal'), isTrue);
      expect(findings.every((f) => f.severity == Severity.warning), isTrue);
    });

    test('ignores placeholders, env names, storage keys and short values', () {
      final findings = _scan('''
const a = 'x';
const password = 'changeme123';
const apiKey = 'YOUR_API_KEY_HERE';
const token = '<token>';
const secret = 'API_KEY';
const authToken = 'auth_token';
const clientSecret = 'short1';
const tokenKey = 'k8Jx92LmQp4Zr7Tv';
const passwordHint = 'k8Jx92LmQp4Zr7Tv';
const note = 'k8Jx92LmQp4Zr7Tv';
''');
      expect(findings, isEmpty);
    });

    test('ignores environment reads and non-literal values', () {
      final findings = _scan(r'''
const apiKey = String.fromEnvironment('API_KEY');
final token = Platform.environment['TOKEN'] ?? 'k8Jx92LmQp4Zr7Tv';
final password = 'pre$x' 'k8Jx92LmQp4Zr7Tv';
final secret = read('k8Jx92LmQp4Zr7Tv');
''');
      expect(findings, isEmpty);
    });
  });

  group('parameter default values', () {
    test('flags a secret default of a named or positional parameter', () {
      final findings = _scan('''
class Cfg {
  const Cfg({this.password = 'q7W3eR9tY2uI5oP1'});
  final String password;
}
void f([String apiKey = 'k8Jx92LmQp4Zr7Tv']) {}
''');
      expect(findings, hasLength(2));
      expect(findings.every((f) => f.kind == 'sensitive-literal'), isTrue);
    });

    test('ignores placeholder defaults and non-sensitive names', () {
      final findings = _scan('''
void f({String password = 'changeme123', String note = 'k8Jx92LmQp4Zr7Tv'}) {}
''');
      expect(findings, isEmpty);
    });
  });

  group('provider formats', () {
    test(
      'flags known formats anywhere, error severity, no site name needed',
      () {
        final findings = _scan('''
final a = '${_j(['AKIA', 'Z7Q4M2XK9PLW3RT5'])}';
final b = '${_j(['ghp_', 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7R8'])}';
final c = '${_j(['sk_live_', 'a1B2c3D4e5F6g7H8'])}';
final d = '${_j(['sk-ant-', 'api03-a1B2c3D4e5F6g7H8i9J0'])}';
final e = '${_j(['-----BEGIN RSA PRIVATE', ' KEY-----'])}\\n${'MIIEowIBAAKCAQEA' * 3}';
final g = '${_j(['xoxb-', '8403917265-a1B2c3D4e5F6'])}';
final h = '${_j(['sk-proj-', 'a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6'])}';
''');
        expect(findings.map((f) => f.kind).toSet(), {'provider-key'});
        expect(findings, hasLength(7));
        expect(findings.every((f) => f.severity == Severity.error), isTrue);
      },
    );

    test('Google API keys are a warning, not an error', () {
      final findings = _scan("final f = '${_j(['AIza', 'Sy' * 17, 'x'])}';");
      expect(findings, hasLength(1));
      expect(findings.single.kind, 'provider-key');
      expect(findings.single.severity, Severity.warning);
    });

    test('one finding when a provider key sits on a sensitive name', () {
      final findings = _scan(
        "const apiKey = '${_j(['AKIA', 'Z7Q4M2XK9PLW3RT5'])}';",
      );
      expect(findings, hasLength(1));
      expect(findings.single.kind, 'provider-key');
    });

    test('ignores sample keys, a bare PEM header and sk- identifiers', () {
      final findings = _scan('''
final a = '${_j(['AKIAIOSFODNN7', 'EXAMPLE'])}';
final b = '${_j(['-----BEGIN PRIVATE', ' KEY-----'])}';
final c = '${_j(['pk_live_', 'a1B2c3D4e5F6g7H8'])}';
final d = 'route-REDACTED';
''');
      expect(findings, isEmpty);
    });
  });

  group('exempt files', () {
    test('test, fixture, example and firebase_options paths are skipped', () {
      for (final path in [
        'test/a_test.dart',
        'lib/foo_test.dart',
        'integration_test/x.dart',
        'test/fixtures/x.dart',
        'example/lib/main.dart',
        'lib/firebase_options.dart',
      ]) {
        expect(isSecretScanExempt(path), isTrue, reason: path);
      }
      expect(isSecretScanExempt('lib/src/config.dart'), isFalse);
      expect(isSecretScanExempt('lib/testing_tools.dart'), isFalse);
    });
  });

  group('masking and fingerprint', () {
    const secret = 'k8Jx92LmQp4Zr7Tv';
    List<Finding> scan(String body) =>
        _scan("class C {\n$body\n  static const apiKey = '$secret';\n}");

    test('value never appears in any finding field', () {
      final f = scan('').single;
      final dump = '${f.message}|${f.remedy}|${f.fingerprint}|${f.kind}';
      expect(dump.contains(secret), isFalse);
    });

    test('fingerprint survives line shifts and value rotation', () {
      final a = scan('').single.fingerprint;
      final b = scan('\n\n  // moved\n').single.fingerprint;
      final rotated = _scan(
        "class C {\n  static const apiKey = 'Zz9Yy8Xx7Ww6Vv5U';\n}",
      ).single.fingerprint;
      expect(b, a);
      expect(rotated, a);
    });

    test('repeated sites in one scope get distinct fingerprints', () {
      final findings = _scan('''
void f() {
  final password = 'k8Jx92LmQp4Zr7Tv';
  final password2 = 'k8Jx92LmQp4Zr7Tv';
  var password = 'q7W3eR9tY2uI5oP1';
}
''');
      expect(
        findings.map((f) => f.fingerprint).toSet(),
        hasLength(findings.length),
      );
    });
  });

  test('is registered in the full rule registry', () {
    expect(AnalysisRunner.fullRegistryIds, contains('hardcoded-secrets'));
  });
}
