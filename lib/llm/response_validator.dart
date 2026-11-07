import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Deterministic checks of Doc 13.17, run before a generated file is executed:
/// the code is non-empty, parses as Dart (so nothing was truncated and all
/// brackets and quotes match) and declares at least one test.
class ResponseValidator {
  const ResponseValidator();

  /// Returns the problems found; empty means the file may be executed.
  List<String> validate(String code) {
    if (code.trim().isEmpty) return const ['The response contains no Dart code.'];

    final result = parseString(content: code, throwIfDiagnostics: false);
    final problems = <String>[
      for (final diagnostic in result.errors)
        if (diagnostic.diagnosticCode.severity == DiagnosticSeverity.ERROR)
          'Syntax error at line ${result.lineInfo.getLocation(diagnostic.offset).lineNumber}: '
              '${diagnostic.message}',
    ];

    final finder = _TestFinder();
    result.unit.accept(finder);
    if (!finder.found) {
      problems.add('The file declares no test (no testWidgets or test call).');
    }
    return problems;
  }
}

class _TestFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (node.target == null && (name == 'testWidgets' || name == 'test')) found = true;
    super.visitMethodInvocation(node);
  }
}
