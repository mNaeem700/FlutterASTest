import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutterastest/parser/models/parser_result.dart';
import '../models/widget_property_model.dart';

class WidgetPropertyAnalyzer {
  const WidgetPropertyAnalyzer();

  List<WidgetPropertyModel> analyse(ParserResult parserResult) {
    final List<WidgetPropertyModel> properties = [];

    for (final unitResult in parserResult.resolvedUnits) {
      final visitor = _PropertyVisitor();
      unitResult.unit.accept(visitor);
      properties.addAll(visitor.extractedProperties);
    }

    return properties;
  }
}

class _PropertyVisitor extends RecursiveAstVisitor<void> {
  final List<WidgetPropertyModel> extractedProperties = [];
  String? currentWidget;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructorName = node.constructorName.type.toSource();
    final previousWidget = currentWidget;
    currentWidget = constructorName;

    for (final argument in node.argumentList.arguments) {
      if (argument is NamedExpression) {
        final propName = argument.name.label.name;
        final exprSource = argument.expression.toSource();

        String valueType = 'Primitive';
        if (exprSource.contains('=>') ||
            exprSource.contains('function') ||
            exprSource.contains('(')) {
          valueType = 'Callback';
        } else if (exprSource.contains('TextStyle') ||
            exprSource.contains('ButtonStyle') ||
            exprSource.contains('BoxDecoration')) {
          valueType = 'StyleObject';
        } else if (exprSource.contains('Widget') ||
            exprSource.contains('Container') ||
            exprSource.contains('Text(')) {
          valueType = 'Widget';
        }

        final category = _categorizePropertyStatic(propName, valueType);

        extractedProperties.add(
          WidgetPropertyModel(
            widgetName: currentWidget ?? 'UnknownWidget',
            propertyName: propName,
            valueType: valueType,
            category: category,
          ),
        );
      }
    }

    super.visitInstanceCreationExpression(node);
    currentWidget = previousWidget;
  }

  String _categorizePropertyStatic(String propName, String valueType) {
    const layoutProps = {
      'padding',
      'margin',
      'alignment',
      'width',
      'height',
      'flex',
      'constraints'
    };
    const stylingProps = {
      'color',
      'decoration',
      'style',
      'backgroundColor',
      'elevation',
      'shape'
    };
    const textProps = {'text', 'data', 'hintText', 'labelText', 'maxLines'};
    const behaviorProps = {
      'onPressed',
      'onTap',
      'onChanged',
      'onSubmitted',
      'onLongPress'
    };
    const stateProps = {'controller', 'initialData', 'value', 'enabled'};

    if (layoutProps.contains(propName)) return 'Layout';
    if (stylingProps.contains(propName)) return 'Styling';
    if (textProps.contains(propName)) return 'Text';
    if (behaviorProps.contains(propName) || valueType == 'Callback')
      return 'Behavior';
    if (stateProps.contains(propName)) return 'State';
    return 'Others';
  }
}
