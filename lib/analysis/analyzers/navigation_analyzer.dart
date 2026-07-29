import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutterastest/parser/models/parser_result.dart';
import '../models/navigation_edge.dart';

class NavigationAnalyzer {
  const NavigationAnalyzer();

  List<NavigationEdge> analyse(ParserResult parserResult) {
    final List<NavigationEdge> edges = [];

    for (final unitResult in parserResult.resolvedUnits) {
      final visitor = _NavigationVisitor();
      unitResult.unit.accept(visitor);
      edges.addAll(visitor.edges);
    }

    return edges;
  }
}

class _NavigationVisitor extends RecursiveAstVisitor<void> {
  final List<NavigationEdge> edges = [];
  String?
      currentClass; // Keep track of which screen/widget we are currently inside

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final previousClass = currentClass;
    currentClass = node.name.lexeme;

    super.visitClassDeclaration(node);

    currentClass = previousClass;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    NavigationType? type;

    // 1. Identify the navigation type based on the method name
    if (methodName == 'push')
      type = NavigationType.push;
    else if (methodName == 'pushReplacement')
      type = NavigationType.pushReplacement;
    else if (methodName == 'pushNamed')
      type = NavigationType.pushNamed;
    else if (methodName == 'popAndPushNamed')
      type = NavigationType.popAndPushNamed;
    else if (methodName == 'go')
      type = NavigationType.go;
    else if (methodName == 'replace') type = NavigationType.replace;

    if (type != null && currentClass != null) {
      String? destination;

      // 2. Extract the destination (String route or Widget Class)
      final args = node.argumentList.arguments;

      if (type == NavigationType.pushNamed ||
          type == NavigationType.popAndPushNamed ||
          type == NavigationType.go ||
          type == NavigationType.replace) {
        // For named routes, usually the route string is passed as an argument (e.g., context.go('/home'))
        for (final arg in args) {
          if (arg is SimpleStringLiteral) {
            destination = arg.value;
            break;
          }
        }
      } else if (type == NavigationType.push ||
          type == NavigationType.pushReplacement) {
        // For MaterialPageRoute, we use a quick string heuristic on the arguments to find the instantiated Widget
        // E.g., MaterialPageRoute(builder: (context) => LoginScreen())
        final argsSource = node.argumentList.toSource();
        final match =
            RegExp(r'=>\s*([A-Z][a-zA-Z0-9_]*)\(').firstMatch(argsSource);

        if (match != null) {
          destination = match.group(1);
        } else {
          // Fallback regex to catch other common builder patterns
          final fallbackMatch =
              RegExp(r'return\s+([A-Z][a-zA-Z0-9_]*)\(').firstMatch(argsSource);
          if (fallbackMatch != null) destination = fallbackMatch.group(1);
        }
      }

      // 3. Record the edge if we successfully found a destination
      if (destination != null) {
        edges.add(
          NavigationEdge(
            fromScreen: currentClass!,
            toScreen: destination,
            navigationType: type,
          ),
        );
      }
    }

    super.visitMethodInvocation(node);
  }
}
