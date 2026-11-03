import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';

/// Returns the name of the declaration that encloses [node], qualified by its
/// enclosing type (class, mixin, enum, extension or extension type).
///
/// Falls back to `'<unknown>'` when [node] sits outside any method or function.
/// Used as the **scope** part of a semantic anchor.
String enclosingMemberName(AstNode node) {
  AstNode? current = node.parent;
  while (current != null) {
    if (current is MethodDeclaration) {
      final owner = ownerTypeName(current);
      final method = current.name.lexeme;
      return owner.isEmpty ? method : '$owner.$method';
    }
    if (current is FunctionDeclaration) return current.name.lexeme;
    current = current.parent;
  }
  return '<unknown>';
}

/// The name of the type declaration that owns [member], or `''` for a
/// top-level declaration.
///
/// Newer analyzer ASTs put members under an intermediate body node
/// (`BlockClassBody`, `EnumBody`, ...) instead of directly under the
/// declaration, so the search walks up to the first type declaration rather
/// than reading `member.parent`.
String ownerTypeName(AstNode member) {
  AstNode? owner = member.parent;
  while (owner != null && owner is! CompilationUnit) {
    final name = _declaredName(owner);
    if (name != null) return name;
    owner = owner.parent;
  }
  return '';
}

String? _declaredName(AstNode owner) => switch (owner) {
  ClassDeclaration() => owner.namePart.typeName.lexeme,
  MixinDeclaration() => owner.name.lexeme,
  EnumDeclaration() => owner.namePart.typeName.lexeme,
  ExtensionTypeDeclaration() => owner.namePart.typeName.lexeme,
  ExtensionDeclaration() =>
    owner.name?.lexeme ?? 'extension on ${owner.onClause?.extendedType}',
  _ => null,
};

/// A formatting-independent, comment-free rendering of [node]'s tokens.
///
/// Trailing commas are dropped. Line breaks inside a token (multi-line
/// strings) are written as `\n`, so a CRLF checkout (Windows,
/// `core.autocrlf`) yields the same content as an LF one. Function bodies (closures, nested functions) are collapsed to `{}`, so
/// editing a callback body does not change the content of the surrounding
/// construct. Line shifts, re-formatting and inserted comments never alter
/// the result.
String normalizedSource(AstNode node) {
  final bodies = <(int, int)>[];
  node.accept(_BodyCollector(bodies));

  final out = StringBuffer();
  Token token = node.beginToken;
  while (true) {
    final body = bodies.where(
      (b) => token.offset >= b.$1 && token.offset < b.$2,
    );
    final trailingComma =
        token.lexeme == ',' &&
        (token.next?.lexeme == ')' || token.next?.lexeme == ']');
    if (trailingComma) {
      // Formatter-added trailing commas are not content.
    } else if (body.isEmpty) {
      out
        ..write(_lfLineBreaks(token.lexeme))
        ..write(' ');
    } else if (token.offset == body.first.$1) {
      out.write('{} ');
    }
    if (identical(token, node.endToken) || token.next == null) break;
    token = token.next!;
  }
  return out.toString().trim();
}

final _lineBreak = RegExp(r'\r\n?');

/// [lexeme] with CRLF and lone CR line breaks written as LF.
String _lfLineBreaks(String lexeme) =>
    lexeme.contains('\r') ? lexeme.replaceAll(_lineBreak, '\n') : lexeme;

class _BodyCollector extends RecursiveAstVisitor<void> {
  _BodyCollector(this.ranges);

  final List<(int, int)> ranges;

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    ranges.add((node.offset, node.end));
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    ranges.add((node.offset, node.end));
  }
}

/// Hands out content-based anchors for occurrences inside one file.
///
/// An anchor is `<scope>:<content-hash>:<n>`. `n` counts only earlier
/// occurrences with the **same scope and content**, so inserting, moving or
/// re-formatting unrelated code never shifts an existing anchor; only true
/// duplicates (identical scope and content) are told apart by their order.
class AnchorCounter {
  final Map<String, int> _seen = {};

  /// Returns the anchor for the next occurrence of [content] within [scope].
  String next(String scope, String content) {
    final hash = sha256
        .convert(utf8.encode(content))
        .toString()
        .substring(0, 10);
    final key = '$scope:$hash';
    final n = _seen[key] ?? 0;
    _seen[key] = n + 1;
    return '$key:$n';
  }
}
