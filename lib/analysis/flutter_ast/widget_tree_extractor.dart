import 'package:analyzer/dart/ast/ast.dart';

import '../models/screen_context_model.dart';
import '../project_index.dart' show locate;
import 'widget_call.dart';

class ExtractedTree {
  const ExtractedTree({
    required this.roots,
    required this.truncated,
    required this.handlers,
  });

  final List<WidgetTreeNode> roots;
  final bool truncated;

  /// Handler argument expressions by node path, then by argument name.
  final Map<String, Map<String, Expression>> handlers;
}

/// Builds the widget tree a build() method returns.
///
/// Only arguments in widget positions are followed (child, children, body,
/// builder closures, ...), so value objects such as EdgeInsets or TextStyle
/// never appear as widgets. Helper methods of the same classes that return
/// widgets are inlined.
class WidgetTreeExtractor {
  WidgetTreeExtractor({
    required Map<String, MethodDeclaration> methods,
    this.maxNodes = 80,
    this.maxDepth = 14,
  }) : _methods = methods;

  final Map<String, MethodDeclaration> _methods;
  final int maxNodes;
  final int maxDepth;

  static const widgetSlots = {
    'child',
    'children',
    'body',
    'appBar',
    'title',
    'subtitle',
    'leading',
    'trailing',
    'actions',
    'bottom',
    'bottomNavigationBar',
    'bottomSheet',
    'floatingActionButton',
    'drawer',
    'endDrawer',
    'home',
    'content',
    'icon',
    'activeIcon',
    'label',
    'flexibleSpace',
    'header',
    'footer',
    'prefix',
    'suffix',
    'placeholder',
    'errorWidget',
    'tabs',
    'items',
    'destinations',
    'slivers',
    'sliver',
    'background',
    'secondaryBackground',
    'avatar',
    'builder',
    'itemBuilder',
  };

  /// Named arguments whose string value a test can find on screen.
  static const _labelArguments = {
    'text',
    'title',
    'label',
    'hintText',
    'labelText',
    'helperText',
    'tooltip',
    'semanticLabel',
    'semanticsLabel',
    'hint',
    'buttonText',
    'message',
  };

  int _count = 0;
  bool _truncated = false;
  Map<String, Map<String, Expression>> _handlers = {};

  ExtractedTree extract(MethodDeclaration build) {
    _count = 0;
    _truncated = false;
    _handlers = {};
    final roots = <WidgetTreeNode>[];
    final returns = returnedExpressions(build.body);
    for (var i = 0; i < returns.length; i++) {
      roots.addAll(_fromExpression(returns[i], '$i', 0, {build.name.lexeme}));
    }
    return ExtractedTree(roots: roots, truncated: _truncated, handlers: _handlers);
  }

  List<WidgetTreeNode> _fromExpression(
      Expression expression, String path, int depth, Set<String> inlined) {
    final node = unwrap(expression);

    if (node is ConditionalExpression) {
      return [
        ..._fromExpression(node.thenExpression, '$path.t', depth, inlined),
        ..._fromExpression(node.elseExpression, '$path.f', depth, inlined),
      ];
    }

    if (node is ListLiteral) {
      return _fromElements(node.elements, path, depth, inlined);
    }

    if (node is FunctionExpression) {
      final results = <WidgetTreeNode>[];
      final returns = returnedExpressions(node.body);
      for (var i = 0; i < returns.length; i++) {
        results.addAll(_fromExpression(returns[i], '$path.$i', depth, inlined));
      }
      return results;
    }

    if (node is MethodInvocation && node.target == null) {
      final helper = _methods[node.methodName.name];
      if (helper != null && !inlined.contains(helper.name.lexeme)) {
        final nested = {...inlined, helper.name.lexeme};
        final returns = returnedExpressions(helper.body);
        return [
          for (var i = 0; i < returns.length; i++)
            ..._fromExpression(returns[i], '$path.$i', depth, nested),
        ];
      }
    }

    final call = asWidgetCall(node);
    if (call == null) return const [];
    final built = _fromCall(call, path, depth, inlined);
    return built == null ? const [] : [built];
  }

  List<WidgetTreeNode> _fromElements(List<CollectionElement> elements,
      String path, int depth, Set<String> inlined) {
    final results = <WidgetTreeNode>[];
    for (var i = 0; i < elements.length; i++) {
      results.addAll(_fromElement(elements[i], '$path.$i', depth, inlined));
    }
    return results;
  }

  List<WidgetTreeNode> _fromElement(
      CollectionElement element, String path, int depth, Set<String> inlined) {
    if (element is Expression) return _fromExpression(element, path, depth, inlined);
    if (element is IfElement) {
      return [
        ..._fromElement(element.thenElement, '$path.t', depth, inlined),
        if (element.elseElement != null)
          ..._fromElement(element.elseElement!, '$path.f', depth, inlined),
      ];
    }
    if (element is ForElement) return _fromElement(element.body, path, depth, inlined);
    if (element is SpreadElement) {
      return _fromExpression(element.expression, path, depth, inlined);
    }
    return const [];
  }

  WidgetTreeNode? _fromCall(
      WidgetCall call, String path, int depth, Set<String> inlined) {
    if (_count >= maxNodes || depth > maxDepth) {
      _truncated = true;
      return null;
    }
    _count++;

    final labels = <String>[];
    String? key;
    final handlers = <String>[];
    final validations = <String>[];
    final children = <WidgetTreeNode>[];
    var childIndex = 0;

    for (final argument in call.positional) {
      final text = stringValue(argument);
      if (text != null) {
        labels.add(text);
        continue;
      }
      final source = argument.toSource();
      if (source.startsWith('Icons.') || source.startsWith('CupertinoIcons.')) {
        labels.add(source);
        continue;
      }
      if (unwrap(argument) is FunctionExpression || asWidgetCall(argument) != null) {
        children.addAll(
            _fromExpression(argument, '$path.${childIndex++}', depth + 1, inlined));
      }
    }

    for (final argument in call.namedArguments) {
      final name = argument.name.label.name;
      final value = argument.expression;

      if (name == 'key') {
        key = _keyValue(value);
        continue;
      }
      if (name == 'validator') {
        validations.addAll(_validationMessages(value));
        continue;
      }
      if (_isHandler(name, value)) {
        handlers.add(name);
        _handlers.putIfAbsent(path, () => {})[name] = value;
        continue;
      }
      if (name == 'decoration') {
        final decoration = asWidgetCall(value);
        if (decoration != null && decoration.type == 'InputDecoration') {
          for (final inner in decoration.namedArguments) {
            final text = stringValue(inner.expression);
            if (text != null && _labelArguments.contains(inner.name.label.name)) {
              labels.add(text);
              continue;
            }
            // InputDecoration(label: Text('Email'), prefixIcon: Icon(Icons.mail))
            final widget = asWidgetCall(inner.expression);
            final first = widget?.positional.firstOrNull;
            if (first == null) continue;
            final value = stringValue(first) ?? first.toSource();
            if (stringValue(first) != null ||
                value.startsWith('Icons.') ||
                value.startsWith('CupertinoIcons.')) {
              labels.add(value);
            }
          }
        }
        continue;
      }

      final text = stringValue(value);
      if (text != null) {
        if (_labelArguments.contains(name)) labels.add(text);
        continue;
      }

      if (widgetSlots.contains(name)) {
        children.addAll(
            _fromExpression(value, '$path.${childIndex++}', depth + 1, inlined));
      }
    }

    return WidgetTreeNode(
      path: path,
      type: call.displayName,
      labels: labels,
      key: key,
      handlers: handlers,
      children: children,
      location: locate(call.node),
      validations: validations,
    );
  }

  List<String> _validationMessages(Expression value) {
    final node = unwrap(value);
    if (node is NullLiteral) return const [];
    final FunctionBody? body = node is FunctionExpression
        ? node.body
        : node is SimpleIdentifier
            ? _methods[node.name]?.body
            : null;
    if (body == null) return ['by ${node.toSource()}'];
    final messages = {for (final e in returnedExpressions(body)) ..._messages(e)};
    return messages.isEmpty ? ['by ${node.toSource()}'] : messages.toList();
  }

  static List<String> _messages(Expression expression) {
    final node = unwrap(expression);
    if (node is ConditionalExpression) {
      return [..._messages(node.thenExpression), ..._messages(node.elseExpression)];
    }
    final text = stringValue(node);
    return text == null ? const [] : [text];
  }

  static bool _isHandler(String name, Expression value) {
    if (!RegExp(r'^on[A-Z]').hasMatch(name)) return false;
    final node = unwrap(value);
    return node is! NullLiteral;
  }

  static String? _keyValue(Expression value) {
    final call = asWidgetCall(value);
    if (call == null) return value.toSource();
    final first = call.positional.firstOrNull;
    if (first == null) return call.displayName;
    return stringValue(first) ?? first.toSource();
  }
}
