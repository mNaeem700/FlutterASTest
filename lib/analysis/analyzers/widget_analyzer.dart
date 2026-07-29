import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutterastest/parser/models/parser_result.dart';
import '../models/widget_model.dart';

class WidgetAnalyzer {
  const WidgetAnalyzer();

  List<WidgetModel> analyse(ParserResult parserResult) {
    final List<WidgetModel> widgets = [];

    // Loop through every resolved file
    for (final unitResult in parserResult.resolvedUnits) {
      final path = unitResult.path;
      final compilationUnit = unitResult.unit;

      // Loop through every declaration in the file
      for (final declaration in compilationUnit.declarations) {
        if (declaration is ClassDeclaration) {
          // Check what the class extends using the AST
          final superclassNode = declaration.extendsClause?.superclass;

          if (superclassNode != null) {
            final superclassName = superclassNode.name2.lexeme;

            if (superclassName == 'StatelessWidget' ||
                superclassName == 'StatefulWidget') {
              widgets.add(
                WidgetModel(
                  name: declaration.name.lexeme,
                  filePath: path,
                  isStateless: superclassName == 'StatelessWidget',
                  isStateful: superclassName == 'StatefulWidget',
                ),
              );
            }
          }
        }
      }
    }

    return widgets;
  }
}
