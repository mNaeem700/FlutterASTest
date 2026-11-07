import 'dart:math';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Maintainability and quality of a generated test file (RQ3, Doc 16.9).
class TestQuality {
  const TestQuality({
    required this.tests,
    required this.linesOfCode,
    required this.assertions,
    required this.smells,
    this.maintainabilityIndex = 0,
  });

  final int tests;
  final int linesOfCode;
  final int assertions;

  /// Test smell name → number of tests that have it.
  final Map<String, int> smells;

  /// Normalized Maintainability Index in [0, 100]; higher is easier to maintain.
  final double maintainabilityIndex;

  double get assertionsPerTest => tests == 0 ? 0 : assertions / tests;
  int get totalSmells => smells.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'tests': tests,
        'linesOfCode': linesOfCode,
        'assertions': assertions,
        'assertionsPerTest': double.parse(assertionsPerTest.toStringAsFixed(2)),
        'smells': smells,
        'totalSmells': totalSmells,
        'maintainabilityIndex': double.parse(maintainabilityIndex.toStringAsFixed(2)),
      };
}

/// Counts tests and assertions and detects test smells statically, following
/// the common catalogue also used for Dart by DNose: empty test, no assertion,
/// sleepy test, conditional logic, print statement, assertion roulette and
/// duplicate test.
class TestQualityAnalyzer {
  const TestQualityAnalyzer();

  static const _rouletteThreshold = 5;

  TestQuality analyse(String code) {
    final unit = parseString(content: code, throwIfDiagnostics: false).unit;
    final collector = _TestCollector();
    unit.accept(collector);

    final smells = <String, int>{};
    void smell(String name) => smells[name] = (smells[name] ?? 0) + 1;
    final bodies = <String>{};
    var assertions = 0;

    for (final body in collector.bodies) {
      final inspector = _BodyInspector();
      body.accept(inspector);
      assertions += inspector.assertions;

      final statements = body is BlockFunctionBody ? body.block.statements.length : 1;
      if (statements == 0) smell('emptyTest');
      if (inspector.assertions == 0) smell('noAssertion');
      if (inspector.sleeps) smell('sleepyTest');
      if (inspector.conditional) smell('conditionalLogic');
      if (inspector.prints) smell('printStatement');
      if (inspector.assertions >= _rouletteThreshold) smell('assertionRoulette');
      if (!bodies.add(body.toSource())) smell('duplicateTest');
    }

    final linesOfCode = code.split('\n').where((l) => l.trim().isNotEmpty).length;
    return TestQuality(
      maintainabilityIndex: _maintainability(unit, linesOfCode),
      tests: collector.bodies.length,
      linesOfCode: linesOfCode,
      assertions: assertions,
      smells: smells,
    );
  }
}

/// MI = max(0, (171 - 5.2 ln V - 0.23 G - 16.2 ln LOC) * 100 / 171), with
/// Halstead volume V from the token stream and cyclomatic complexity G from
/// branching tokens (Oman and Hagemeister, in the normalized form).
double _maintainability(CompilationUnit unit, int linesOfCode) {
  const branching = {'if', 'for', 'while', 'case', 'catch', '&&', '||', '??', '?'};
  final distinct = <String>{};
  var total = 0, complexity = 1;
  Token token = unit.beginToken;
  while (token.type != TokenType.EOF) {
    total++;
    distinct.add(token.lexeme);
    if (branching.contains(token.lexeme)) complexity++;
    token = token.next!;
  }
  if (total == 0 || linesOfCode == 0) return 100;
  final volume = total * (log(max(distinct.length, 2)) / ln2);
  final index = 171 - 5.2 * log(volume) - 0.23 * complexity - 16.2 * log(linesOfCode);
  return (index * 100 / 171).clamp(0, 100).toDouble();
}

class _TestCollector extends RecursiveAstVisitor<void> {
  final bodies = <FunctionBody>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (node.target == null && (name == 'testWidgets' || name == 'test')) {
      for (final argument in node.argumentList.arguments) {
        if (argument is FunctionExpression) bodies.add(argument.body);
      }
      return;
    }
    super.visitMethodInvocation(node);
  }
}

class _BodyInspector extends RecursiveAstVisitor<void> {
  int assertions = 0;
  bool sleeps = false;
  bool conditional = false;
  bool prints = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final receiver = node.target?.toSource();
    if (name == 'expect' || name == 'expectLater') assertions++;
    if (name == 'sleep' || (receiver == 'Future' && name == 'delayed')) sleeps = true;
    if (name == 'print' || name == 'debugPrint') prints = true;
    super.visitMethodInvocation(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    conditional = true;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    conditional = true;
    super.visitForStatement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    conditional = true;
    super.visitWhileStatement(node);
  }
}
