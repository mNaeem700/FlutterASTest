import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Maintainability and quality of a generated test file (RQ3, Doc 16.9).
class TestQuality {
  const TestQuality({
    required this.tests,
    required this.linesOfCode,
    required this.assertions,
    required this.smells,
  });

  final int tests;
  final int linesOfCode;
  final int assertions;

  /// Test smell name → number of tests that have it.
  final Map<String, int> smells;

  double get assertionsPerTest => tests == 0 ? 0 : assertions / tests;
  int get totalSmells => smells.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'tests': tests,
        'linesOfCode': linesOfCode,
        'assertions': assertions,
        'assertionsPerTest': double.parse(assertionsPerTest.toStringAsFixed(2)),
        'smells': smells,
        'totalSmells': totalSmells,
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

    return TestQuality(
      tests: collector.bodies.length,
      linesOfCode: code.split('\n').where((l) => l.trim().isNotEmpty).length,
      assertions: assertions,
      smells: smells,
    );
  }
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
