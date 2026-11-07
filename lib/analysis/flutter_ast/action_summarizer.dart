import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../models/screen_context_model.dart';
import '../project_index.dart' show locate;
import 'widget_call.dart';

/// Recognises Navigator, GetX, go_router and auto_route navigation calls.
class NavigationDetector {
  const NavigationDetector({this.knownWidgets = const {}});

  /// Project widget classes; preferred when picking a push destination.
  final Set<String> knownWidgets;

  static const _navigatorMethods = {
    'push': NavigationKind.push,
    'pushNamed': NavigationKind.push,
    'pushReplacement': NavigationKind.replace,
    'pushReplacementNamed': NavigationKind.replace,
    'popAndPushNamed': NavigationKind.replace,
    'pushAndRemoveUntil': NavigationKind.clearStack,
    'pushNamedAndRemoveUntil': NavigationKind.clearStack,
    'pop': NavigationKind.pop,
    'maybePop': NavigationKind.pop,
    'popUntil': NavigationKind.pop,
  };

  static const _getMethods = {
    'to': NavigationKind.push,
    'toNamed': NavigationKind.push,
    'off': NavigationKind.replace,
    'offNamed': NavigationKind.replace,
    'offAll': NavigationKind.clearStack,
    'offAllNamed': NavigationKind.clearStack,
    'offUntil': NavigationKind.clearStack,
    'back': NavigationKind.pop,
    'until': NavigationKind.pop,
  };

  static const _routerMethods = {
    'go': NavigationKind.replace,
    'goNamed': NavigationKind.replace,
    'push': NavigationKind.push,
    'pushNamed': NavigationKind.push,
    'pushReplacement': NavigationKind.replace,
    'pushReplacementNamed': NavigationKind.replace,
    'replace': NavigationKind.replace,
    'replaceNamed': NavigationKind.replace,
    'navigate': NavigationKind.push,
    'pop': NavigationKind.pop,
  };

  /// Classes that wrap the destination rather than being the destination.
  static const _routeWrappers = {
    'MaterialPageRoute',
    'CupertinoPageRoute',
    'PageRouteBuilder',
    'PageTransition',
    'GetPageRoute',
    'RouteSettings',
    'Duration',
    'Offset',
    'Tween',
    'CurvedAnimation',
    'SlideTransition',
    'FadeTransition',
    'ScaleTransition',
  };

  NavigationTarget? detect(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.realTarget;
    if (target == null) return null;
    final receiver = target.toSource();

    NavigationKind? kind;
    String api;

    if (receiver == 'Navigator' || receiver.startsWith('Navigator.of(')) {
      kind = _navigatorMethods[method];
      api = 'Navigator.$method';
    } else if (receiver == 'Get') {
      kind = _getMethods[method];
      api = 'Get.$method';
    } else if (receiver == 'context' ||
        receiver.endsWith('.router') ||
        receiver.startsWith('GoRouter.of(') ||
        receiver.startsWith('AutoRouter.of(')) {
      kind = _routerMethods[method];
      api = receiver == 'context' ? 'context.$method' : '$receiver.$method';
    } else {
      return null;
    }

    if (kind == null) return null;
    if (kind == NavigationKind.pop) {
      return NavigationTarget(api: api, kind: kind);
    }

    final isNamed = method.toLowerCase().contains('named') || method == 'go';
    if (isNamed) {
      final first = node.argumentList.arguments
          .where((a) => a is! NamedExpression)
          .firstOrNull;
      final route = first == null ? null : (stringValue(first) ?? first.toSource());
      return NavigationTarget(api: api, kind: kind, target: route, isRouteName: true);
    }

    return NavigationTarget(api: api, kind: kind, target: _destination(node.argumentList));
  }

  String? _destination(ArgumentList arguments) {
    final finder = _WidgetCallFinder();
    arguments.accept(finder);
    final candidates =
        finder.types.where((t) => !_routeWrappers.contains(t)).toList();
    return candidates.firstWhere(knownWidgets.contains,
        orElse: () => candidates.isEmpty ? '' : candidates.first).nullIfEmpty;
  }
}

class _WidgetCallFinder extends RecursiveAstVisitor<void> {
  final List<String> types = [];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    types.add(node.constructorName.type.name.lexeme);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final call = asWidgetCall(node);
    if (call != null) types.add(call.type);
    super.visitMethodInvocation(node);
  }
}

/// Summarises what a block of code does: calls, navigation, state changes and
/// UI side effects, and where each of them happens. Private helper methods of
/// the same classes are followed up to [maxDepth] levels so `onTap: _login`
/// is attributed correctly.
class ActionSummarizer {
  ActionSummarizer({
    required Map<String, MethodDeclaration> methods,
    required NavigationDetector navigation,
    this.maxDepth = 2,
  })  : _methods = methods,
        _navigation = navigation;

  final Map<String, MethodDeclaration> _methods;
  final NavigationDetector _navigation;
  final int maxDepth;

  static const _ignoredReceivers = {
    'context',
    'MediaQuery',
    'Theme',
    'FocusScope',
    'FocusManager',
    'print',
  };

  static const _effectCalls = {
    'showDialog': 'showDialog',
    'showModalBottomSheet': 'showModalBottomSheet',
    'showCupertinoDialog': 'showCupertinoDialog',
    'showDatePicker': 'showDatePicker',
    'showTimePicker': 'showTimePicker',
    'showSnackBar': 'SnackBar',
    'snackbar': 'Get.snackbar',
    'dialog': 'Get.dialog',
    'defaultDialog': 'Get.defaultDialog',
    'bottomSheet': 'Get.bottomSheet',
    'showToast': 'toast',
  };

  ActionSummary summarize(AstNode node, {bool isAsync = false}) {
    final collector = _ActionCollector(this, depth: 0, visited: {});
    node.accept(collector);
    return collector.build(isAsync: isAsync);
  }

  /// Summary of a callback expression passed as an event handler argument.
  ActionSummary summarizeHandler(Expression handler) {
    final node = unwrap(handler);
    if (node is ConditionalExpression) {
      // `loading ? null : () => submit()`: either branch may run, so the
      // handler can do anything either branch does.
      final branches = [
        for (final branch in [node.thenExpression, node.elseExpression])
          if (unwrap(branch) is! NullLiteral) summarizeHandler(branch),
      ];
      return ActionSummary(
        calls: {for (final b in branches) ...b.calls}.toList(),
        navigation: {for (final b in branches) ...b.navigation}.toList(),
        stateChanges: {for (final b in branches) ...b.stateChanges}.toList(),
        effects: {for (final b in branches) ...b.effects}.toList(),
        isAsync: branches.any((b) => b.isAsync),
        sites: {for (final b in branches) ...b.sites}.toList(),
        events: {for (final b in branches) ...b.events}.toList(),
      );
    }
    if (node is FunctionExpression) {
      return summarize(node.body, isAsync: node.body.isAsynchronous);
    }
    if (node is SimpleIdentifier) {
      final method = _methods[node.name];
      if (method != null) {
        final inner = summarize(method.body, isAsync: method.body.isAsynchronous);
        return ActionSummary(
          calls: [node.name, ...inner.calls],
          navigation: inner.navigation,
          stateChanges: inner.stateChanges,
          effects: inner.effects,
          isAsync: inner.isAsync,
          sites: inner.sites,
          events: inner.events,
        );
      }
      return ActionSummary(calls: [node.name]);
    }
    return ActionSummary(calls: [node.toSource()]);
  }

  /// The code that runs when [handler] fires: the statements of a closure, or
  /// the body of the method a tear-off or one-line closure calls. Null when
  /// the handler does nothing or its code is not in the project.
  SourceLocation? handlerBody(Expression handler) {
    final node = unwrap(handler);
    if (node is ConditionalExpression) {
      for (final branch in [node.elseExpression, node.thenExpression]) {
        if (unwrap(branch) is NullLiteral) continue;
        final location = handlerBody(branch);
        if (location != null) return location;
      }
      return null;
    }
    if (node is SimpleIdentifier) return _bodyOf(_methods[node.name]?.body);
    if (node is FunctionExpression) {
      final body = node.body;
      if (body is ExpressionFunctionBody) {
        final expression = unwrap(body.expression);
        if (expression is MethodInvocation && expression.target == null) {
          final method = _bodyOf(_methods[expression.methodName.name]?.body);
          if (method != null) return method;
        }
      }
      return _bodyOf(body);
    }
    return null;
  }

  static SourceLocation? _bodyOf(FunctionBody? body) {
    if (body is BlockFunctionBody) {
      final statements = body.block.statements;
      if (statements.isEmpty) return null;
      final first = locate(statements.first);
      final last = locate(statements.last);
      if (first == null || last == null) return null;
      return SourceLocation(
          file: first.file, offset: first.offset, line: first.line, endLine: last.endLine);
    }
    if (body is ExpressionFunctionBody) return locate(body.expression);
    return null;
  }
}

class _ActionCollector extends RecursiveAstVisitor<void> {
  _ActionCollector(this._owner, {required this.depth, required this.visited});

  final ActionSummarizer _owner;
  final int depth;
  final Set<String> visited;

  final calls = <String>{};
  final navigation = <NavigationTarget>{};
  final stateChanges = <String>{};
  final effects = <String>{};
  final sites = <ActionSite>{};
  final events = <String>{};
  bool sawAwait = false;

  ActionSummary build({required bool isAsync}) => ActionSummary(
        calls: calls.toList(),
        navigation: navigation.toList(),
        stateChanges: stateChanges.toList(),
        effects: effects.toList(),
        isAsync: isAsync || sawAwait,
        sites: sites.toList(),
        events: events.toList(),
      );

  void _site(SiteKind kind, String description, AstNode node) {
    final location = locate(node);
    if (location != null) {
      sites.add(ActionSite(kind: kind, description: description, location: location));
    }
  }

  void _stateChange(String description, AstNode node) {
    stateChanges.add(description);
    _site(SiteKind.stateChange, description, node);
  }

  void _effect(String description, AstNode node) {
    effects.add(description);
    _site(SiteKind.effect, description, node);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    sawAwait = true;
    super.visitAwaitExpression(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final left = node.leftHandSide.toSource();
    if (left.endsWith('.value')) _stateChange('.value', node);
    if (left == 'state' || left == 'this.state') _stateChange('state =', node);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    if (type == 'Timer') _effect('Timer(${_firstArgument(node.argumentList)})', node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function.toSource().replaceAll('!', '').replaceAll('?.call', '');
    calls.add(function);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.realTarget;

    final nav = _owner._navigation.detect(node);
    if (nav != null) {
      navigation.add(nav);
      _site(SiteKind.navigation, nav.describe(), node);
      return;
    }

    if (target == null && method == 'setState') {
      _stateChange('setState', node);
      super.visitMethodInvocation(node);
      return;
    }

    if (target == null && _stateMethods.contains(method)) _stateChange('$method()', node);
    if (method == 'notifyListeners' && target != null) _stateChange('notifyListeners()', node);

    final effect = ActionSummarizer._effectCalls[method];
    if (effect != null) {
      _effect(effect, node);
      super.visitMethodInvocation(node);
      return;
    }

    if (target == null) {
      if (method == 'Timer' || isTypeName(method)) {
        if (method == 'Timer') _effect('Timer(${_firstArgument(node.argumentList)})', node);
      } else if (method != 'print' && method != 'debugPrint') {
        calls.add(method);
        _follow(method);
      }
    } else {
      final receiver = target.toSource();
      if (receiver == 'Future' && method == 'delayed') {
        _effect('Future.delayed(${_firstArgument(node.argumentList)})', node);
      } else if (!ActionSummarizer._ignoredReceivers.contains(receiver) &&
          receiver != 'super' &&
          !receiver.startsWith('Navigator') &&
          !receiver.startsWith('MediaQuery') &&
          !receiver.startsWith('Theme.of')) {
        final compact = _compactReceiver(receiver);
        calls.add('$compact.$method');
        if (method == 'add' && node.argumentList.arguments.isNotEmpty) {
          final event = asWidgetCall(node.argumentList.arguments.first);
          if (event != null) events.add('$compact|${event.type}');
        }
        // a.b().c().d() is one call; only arguments of the inner links can
        // contain further actions, so do not record b and c separately.
        _visitChainArguments(target);
        node.argumentList.accept(this);
        return;
      }
    }

    super.visitMethodInvocation(node);
  }

  /// GetX update, Provider notifyListeners, Bloc/Cubit emit, MobX runInAction.
  static const _stateMethods = {'update', 'notifyListeners', 'emit', 'runInAction'};

  void _visitChainArguments(Expression target) {
    Expression? current = target;
    while (current != null) {
      current = unwrap(current);
      if (current is MethodInvocation) {
        current.argumentList.accept(this);
        current = current.target;
      } else if (current is PropertyAccess) {
        current = current.target;
      } else {
        return;
      }
    }
  }

  void _follow(String method) {
    if (depth >= _owner.maxDepth || visited.contains(method)) return;
    final declaration = _owner._methods[method];
    if (declaration == null) return;

    final nested = _ActionCollector(_owner, depth: depth + 1, visited: {...visited, method});
    declaration.body.accept(nested);
    calls.addAll(nested.calls);
    navigation.addAll(nested.navigation);
    stateChanges.addAll(nested.stateChanges);
    effects.addAll(nested.effects);
    sites.addAll(nested.sites);
    events.addAll(nested.events);
    if (declaration.body.isAsynchronous || nested.sawAwait) sawAwait = true;
  }

  String _firstArgument(ArgumentList arguments) =>
      arguments.arguments.isEmpty ? '' : arguments.arguments.first.toSource();

  /// `Get.find<AuthController>()` → `AuthController`; long chains are shortened.
  String _compactReceiver(String receiver) {
    final find = RegExp(
            r'^(?:Get\.(?:find|put)|context\.(?:read|watch)|(?:Provider|BlocProvider)\.of)<(\w+)>\(.*\)$')
        .firstMatch(receiver);
    if (find != null) return find.group(1)!;
    return receiver.length > 60 ? '${receiver.substring(0, 57)}...' : receiver;
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
