import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// A constructor call that may build a widget.
///
/// Resolved code represents `Text('a')` as an [InstanceCreationExpression];
/// code with unresolved imports represents the same call as a
/// [MethodInvocation]. Both forms are recognised so analysis does not depend
/// on `flutter pub get` having succeeded for the target project.
class WidgetCall {
  const WidgetCall({
    required this.type,
    required this.arguments,
    required this.node,
    this.constructor,
    this.typeArguments = const [],
  });

  final String type;
  final String? constructor;
  final List<TypeAnnotation> typeArguments;
  final ArgumentList arguments;
  final Expression node;

  String get displayName => constructor == null ? type : '$type.$constructor';

  Expression? named(String name) {
    for (final argument in arguments.arguments) {
      if (argument is NamedExpression && argument.name.label.name == name) {
        return argument.expression;
      }
    }
    return null;
  }

  Iterable<Expression> get positional =>
      arguments.arguments.where((a) => a is! NamedExpression);

  Iterable<NamedExpression> get namedArguments =>
      arguments.arguments.whereType<NamedExpression>();

  String? typeArgument(int index) => index < typeArguments.length
      ? _typeName(typeArguments[index])
      : null;

  static String? _typeName(TypeAnnotation annotation) =>
      annotation is NamedType ? annotation.name.lexeme : annotation.toSource();
}

/// Receivers whose static methods are API calls, not named widget constructors.
const _staticApiReceivers = {
  'Get',
  'Navigator',
  'MediaQuery',
  'Theme',
  'Provider',
  'BlocProvider',
  'RepositoryProvider',
  'GoRouter',
  'AutoRouter',
  'ScaffoldMessenger',
  'Future',
  'Stream',
  'Timer',
  'Duration',
  'DateTime',
  'Uri',
  'Colors',
  'Icons',
  'FirebaseAuth',
  'FirebaseFirestore',
  'SharedPreferences',
  'Fluttertoast',
  'SystemChrome',
  'Platform',
  'Math',
  'File',
  'Directory',
};

const _staticApiMethods = {'of', 'maybeOf', 'instance', 'find', 'put'};

Expression unwrap(Expression expression) {
  var current = expression;
  while (current is ParenthesizedExpression) {
    current = current.expression;
  }
  return current;
}

bool isTypeName(String name) {
  final stripped = name.startsWith('_') ? name.substring(1) : name;
  return stripped.isNotEmpty &&
      stripped[0].toUpperCase() == stripped[0] &&
      stripped[0].toLowerCase() != stripped[0];
}

WidgetCall? asWidgetCall(Expression expression) {
  final node = unwrap(expression);

  if (node is InstanceCreationExpression) {
    final type = node.constructorName.type;
    return WidgetCall(
      type: type.name.lexeme,
      constructor: node.constructorName.name?.name,
      typeArguments: type.typeArguments?.arguments ?? const [],
      arguments: node.argumentList,
      node: node,
    );
  }

  if (node is MethodInvocation) {
    final method = node.methodName.name;
    final target = node.target;

    if (target == null && isTypeName(method)) {
      return WidgetCall(
        type: method,
        typeArguments: node.typeArguments?.arguments ?? const [],
        arguments: node.argumentList,
        node: node,
      );
    }

    if (target is SimpleIdentifier &&
        isTypeName(target.name) &&
        !_staticApiReceivers.contains(target.name) &&
        !_staticApiMethods.contains(method) &&
        !isTypeName(method)) {
      return WidgetCall(
        type: target.name,
        constructor: method,
        typeArguments: node.typeArguments?.arguments ?? const [],
        arguments: node.argumentList,
        node: node,
      );
    }
  }

  return null;
}

/// The literal text of a string expression; interpolations keep their source.
String? stringValue(Expression expression) {
  final node = unwrap(expression);
  if (node is SimpleStringLiteral) return node.value;
  if (node is AdjacentStrings) return node.stringValue ?? node.toSource();
  if (node is StringInterpolation) {
    final source = node.toSource();
    return source.length > 2 ? source.substring(1, source.length - 1) : source;
  }
  return null;
}

/// Statements and expressions returned by a function body, without descending
/// into nested closures.
List<Expression> returnedExpressions(FunctionBody body) {
  if (body is ExpressionFunctionBody) return [body.expression];
  if (body is BlockFunctionBody) {
    final collector = _ReturnCollector();
    body.block.accept(collector);
    return collector.expressions;
  }
  return const [];
}

class _ReturnCollector extends RecursiveAstVisitor<void> {
  final List<Expression> expressions = [];

  @override
  void visitReturnStatement(ReturnStatement node) {
    final expression = node.expression;
    if (expression != null) expressions.add(expression);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {}
}

/// All methods declared by any of [classes], by name.
Map<String, MethodDeclaration> methodsOf(Iterable<ClassDeclaration> classes) {
  final methods = <String, MethodDeclaration>{};
  for (final declaration in classes) {
    for (final member in declaration.members) {
      if (member is MethodDeclaration) {
        methods.putIfAbsent(member.name.lexeme, () => member);
      }
    }
  }
  return methods;
}
