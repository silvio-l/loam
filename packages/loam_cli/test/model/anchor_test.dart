import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:loam/src/model/anchor.dart';
import 'package:test/test.dart';

/// Collects the scope name of every `marker()` call in [source].
List<String> scopesOf(String source) {
  final unit = parseString(content: source).unit;
  final scopes = <String>[];
  unit.accept(_MarkerVisitor(scopes));
  return scopes;
}

class _MarkerVisitor extends RecursiveAstVisitor<void> {
  _MarkerVisitor(this.scopes);

  final List<String> scopes;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'marker') {
      scopes.add(enclosingMemberName(node));
    }
    super.visitMethodInvocation(node);
  }
}

void main() {
  test('qualifies members by their enclosing type', () {
    final scopes = scopesOf('''
class A { void build() { marker(); } }
class B { void build() { marker(); } }
mixin M { void run() { marker(); } }
enum E { x; void run() { marker(); } }
extension X on int { void run() { marker(); } }
extension type T(int v) { void run() { marker(); } }
extension on String { void run() { marker(); } }
''');
    expect(scopes, [
      'A.build',
      'B.build',
      'M.run',
      'E.run',
      'X.run',
      'T.run',
      'extension on String.run',
    ]);
  });

  test('top-level functions and code outside any member stay unqualified', () {
    final scopes = scopesOf('''
void top() { marker(); }
final field = marker();
''');
    expect(scopes, ['top', '<unknown>']);
  });
}
