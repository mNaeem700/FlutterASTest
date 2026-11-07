import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// One small fault injected into a source file.
class Mutant {
  const Mutant({
    required this.offset,
    required this.length,
    required this.replacement,
    required this.operator,
    required this.line,
  });

  final int offset;
  final int length;
  final String replacement;

  /// ROR relational, LOR logical, AOR arithmetic, BCR boolean, SDL statement deletion.
  final String operator;
  final int line;

  String apply(String source) =>
      source.replaceRange(offset, offset + length, replacement);

  String get id => '$operator@$line:$offset';
}

/// Generates mutants with the classic operators, inside the given classes.
/// The same source and limit always give the same mutants.
class Mutator {
  const Mutator();

  List<Mutant> generate(String source, {Set<String>? classes, int limit = 20}) {
    final result = parseString(content: source, throwIfDiagnostics: false);
    final collector = _MutantCollector(result.lineInfo.getLocation);
    for (final declaration in result.unit.declarations.whereType<ClassDeclaration>()) {
      if (classes == null || classes.contains(declaration.name.lexeme)) {
        declaration.accept(collector);
      }
    }
    final mutants = collector.mutants..sort((a, b) => a.offset.compareTo(b.offset));
    if (mutants.length <= limit) return mutants;
    // An even spread keeps every part of the screen represented.
    return [for (var i = 0; i < limit; i++) mutants[i * mutants.length ~/ limit]];
  }
}

class _MutantCollector extends RecursiveAstVisitor<void> {
  _MutantCollector(this._location);

  final dynamic Function(int) _location;
  final mutants = <Mutant>[];

  static const _binary = {
    '==': ('!=', 'ROR'),
    '!=': ('==', 'ROR'),
    '<': ('>=', 'ROR'),
    '<=': ('>', 'ROR'),
    '>': ('<=', 'ROR'),
    '>=': ('<', 'ROR'),
    '&&': ('||', 'LOR'),
    '||': ('&&', 'LOR'),
    '+': ('-', 'AOR'),
    '-': ('+', 'AOR'),
    '*': ('~/', 'AOR'),
  };

  void _add(int offset, int length, String replacement, String operator) {
    mutants.add(Mutant(
      offset: offset,
      length: length,
      replacement: replacement,
      operator: operator,
      line: _location(offset).lineNumber as int,
    ));
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final mutation = _binary[node.operator.lexeme];
    // `+` on strings cannot become `-`; such a mutant would not compile.
    final isText = node.leftOperand is StringLiteral || node.rightOperand is StringLiteral;
    if (mutation != null && !(mutation.$2 == 'AOR' && isText)) {
      _add(node.operator.offset, node.operator.length, mutation.$1, mutation.$2);
    }
    super.visitBinaryExpression(node);
  }

  void _step(Token token) {
    if (token.lexeme == '++') _add(token.offset, token.length, '--', 'AOR');
    if (token.lexeme == '--') _add(token.offset, token.length, '++', 'AOR');
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _step(node.operator);
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _step(node.operator);
    super.visitPrefixExpression(node);
  }

  @override
  void visitBooleanLiteral(BooleanLiteral node) {
    _add(node.offset, node.length, node.value ? 'false' : 'true', 'BCR');
    super.visitBooleanLiteral(node);
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    final expression = node.expression;
    final call = expression is AwaitExpression ? expression.expression : expression;
    if (call is MethodInvocation && call.target is! SuperExpression) {
      _add(node.offset, node.length, ';', 'SDL');
    }
    super.visitExpressionStatement(node);
  }
}
