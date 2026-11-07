import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'widget_call.dart';

/// Maps route names to the widget they open, from `GetPage`, `GoRoute` and
/// `routes: {...}` maps, so `Get.toNamed(Routes.login)` can be linked to its
/// screen. Keys are the literal string, or the source text of a constant,
/// matching how navigation calls record their route.
class RouteTable {
  const RouteTable();

  Map<String, String> build(Iterable<CompilationUnit> units, Set<String> knownWidgets) {
    final collector = _RouteCollector(knownWidgets);
    for (final unit in units) {
      unit.accept(collector);
    }
    final routes = collector.routes;
    for (final unit in units) {
      for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
        _addHelpers(declaration, routes);
      }
    }
    return routes;
  }
}

/// A common GetX pattern: `static String getLogin() => login;`, or with
/// `'$login'`. A call to such a helper opens the same route as the name it
/// returns, so `Routes.getLogin()` becomes a key too. A constant's literal
/// value is also a key, for navigation that uses the string directly.
void _addHelpers(ClassDeclaration declaration, Map<String, String> routes) {
  final owner = declaration.name.lexeme;
  String? widgetFor(String name) => routes['$owner.$name'] ?? routes[name];

  for (final member in declaration.members) {
    if (member is FieldDeclaration) {
      for (final variable in member.fields.variables) {
        final value = variable.initializer == null ? null : stringValue(variable.initializer!);
        final widget = widgetFor(variable.name.lexeme);
        if (value != null && widget != null) routes.putIfAbsent(value, () => widget);
      }
    } else if (member is MethodDeclaration && member.isStatic && !member.isGetter) {
      final returned = returnedExpressions(member.body);
      if (returned.isEmpty) continue;
      final node = unwrap(returned.first);
      String? name;
      if (node is SimpleIdentifier) name = node.name;
      if (node is StringInterpolation) {
        final first = node.elements.whereType<InterpolationExpression>().firstOrNull?.expression;
        if (first is SimpleIdentifier) name = first.name;
      }
      final widget = name == null ? null : widgetFor(name);
      if (widget != null) routes.putIfAbsent('$owner.${member.name.lexeme}()', () => widget);
    }
  }
}

class _RouteCollector extends RecursiveAstVisitor<void> {
  _RouteCollector(this._knownWidgets);

  final Set<String> _knownWidgets;
  final routes = <String, String>{};
  String? _class;

  void _addRoute(Expression key, String widget) {
    routes.putIfAbsent(stringValue(key) ?? key.toSource(), () => widget);
    final node = unwrap(key);
    if (node is SimpleIdentifier && _class != null) {
      routes.putIfAbsent('$_class.${node.name}', () => widget);
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final previous = _class;
    _class = node.name.lexeme;
    super.visitClassDeclaration(node);
    _class = previous;
  }

  void _call(WidgetCall call) {
    final builder = switch (call.type) {
      'GetPage' => call.named('page'),
      'GoRoute' => call.named('builder') ?? call.named('pageBuilder'),
      _ => null,
    };
    if (builder == null) return;
    final widget = _widgetIn(builder);
    if (widget == null) return;
    for (final name in const ['name', 'path']) {
      final key = call.named(name);
      if (key != null) _addRoute(key, widget);
    }
  }

  String? _widgetIn(Expression expression) {
    final finder = _KnownWidgetFinder(_knownWidgets);
    expression.accept(finder);
    return finder.found;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final call = asWidgetCall(node);
    if (call != null) _call(call);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final call = asWidgetCall(node);
    if (call != null) _call(call);
    super.visitMethodInvocation(node);
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    for (final element in node.elements) {
      if (element is! MapLiteralEntry || unwrap(element.value) is! FunctionExpression) continue;
      final widget = _widgetIn(element.value);
      if (widget != null) _addRoute(element.key, widget);
    }
    super.visitSetOrMapLiteral(node);
  }
}

class _KnownWidgetFinder extends RecursiveAstVisitor<void> {
  _KnownWidgetFinder(this._known);

  final Set<String> _known;
  String? found;

  void _check(Expression node) {
    final type = asWidgetCall(node)?.type;
    if (found == null && type != null && _known.contains(type)) found = type;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _check(node);
    super.visitMethodInvocation(node);
  }
}
