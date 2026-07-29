import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutterastest/parser/models/parser_result.dart';
import '../models/widget_edge.dart';

class HierarchyAnalyzer {
  const HierarchyAnalyzer();

  List<WidgetEdge> analyse(ParserResult parserResult) {
    final Set<WidgetEdge> edges =
        {}; // Using a Set to avoid duplicate identical edges

    for (final unitResult in parserResult.resolvedUnits) {
      final visitor = _HierarchyVisitor();
      unitResult.unit.accept(visitor);
      edges.addAll(visitor.edges);
    }

    return edges.toList();
  }
}

// Custom AST Visitor to track nested widget constructors
class _HierarchyVisitor extends RecursiveAstVisitor<void> {
  final Set<WidgetEdge> edges = {};
  String? currentParent;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // Get the name of the class being instantiated
    final className = node.constructorName.type.toSource();

    // Heuristic: Flutter widgets are typically capitalized classes
    final isCapitalized =
        className.isNotEmpty && className[0] == className[0].toUpperCase();

    if (isCapitalized) {
      final previousParent = currentParent;

      // If we are already inside a parent widget, record the edge!
      if (previousParent != null) {
        edges.add(WidgetEdge(parent: previousParent, child: className));
      }

      // Set this widget as the new parent for any nested widgets
      currentParent = className;

      // Continue traversing down the tree
      super.visitInstanceCreationExpression(node);

      // Restore the previous parent on the way back up
      currentParent = previousParent;
    } else {
      super.visitInstanceCreationExpression(node);
    }
  }
}
