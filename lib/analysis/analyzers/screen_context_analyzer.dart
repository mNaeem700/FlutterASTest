import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../flutter_ast/action_summarizer.dart';
import '../flutter_ast/widget_call.dart';
import '../flutter_ast/widget_tree_extractor.dart';
import '../models/screen_context_model.dart';
import '../models/screen_model.dart';
import '../project_index.dart';

/// Extracts, for every screen, the context a test author needs.
class ScreenContextAnalyzer {
  const ScreenContextAnalyzer();

  static const _lifecycleMethods = [
    'initState',
    'didChangeDependencies',
    'didUpdateWidget',
    'dispose',
  ];

  List<ScreenContextModel> analyse(ProjectIndex index, List<ScreenModel> screens) {
    final detector = NavigationDetector(knownWidgets: index.widgetClasses.keys.toSet());
    final results = <ScreenContextModel>[];

    for (final screen in screens) {
      final widget = index.widgetClasses[screen.name];
      if (widget == null) continue;
      results.add(_analyseScreen(index, widget, detector));
    }

    results.sort((a, b) => a.name.compareTo(b.name));
    return results;
  }

  ScreenContextModel _analyseScreen(
      ProjectIndex index, ClassRef widget, NavigationDetector detector) {
    final state = index.stateClassOf[widget.name];
    final classes = [
      if (state != null) state.declaration,
      widget.declaration,
    ];
    final methods = methodsOf(classes);
    final summarizer = ActionSummarizer(methods: methods, navigation: detector);

    final build = methods['build'];
    ExtractedTree tree = const ExtractedTree(roots: [], truncated: false, handlers: {});
    if (build != null) {
      tree = WidgetTreeExtractor(methods: methods).extract(build);
    }

    final interactions = <InteractionModel>[];
    void collectInteractions(WidgetTreeNode node) {
      final handlers = tree.handlers[node.path] ?? const {};
      for (final event in node.handlers) {
        final expression = handlers[event];
        if (expression == null) continue;
        interactions.add(InteractionModel(
          widgetPath: node.path,
          widgetType: node.type,
          event: event,
          label: node.firstLabel,
          key: node.key,
          action: summarizer.summarizeHandler(expression),
          location: locate(expression),
          bodyLocation: summarizer.handlerBody(expression),
        ));
      }
      node.children.forEach(collectInteractions);
    }

    tree.roots.forEach(collectInteractions);

    final dependencyCollector = _DependencyCollector(index, widget, state);
    final dependencies = dependencyCollector.collect();
    final delegates = _DelegateResolver(index, detector, dependencyCollector.variableTypes);

    final resolvedInteractions = [
      for (final interaction in interactions)
        InteractionModel(
          widgetPath: interaction.widgetPath,
          widgetType: interaction.widgetType,
          event: interaction.event,
          label: interaction.label,
          key: interaction.key,
          action: delegates.resolve(interaction.action),
          location: interaction.location,
          bodyLocation: interaction.bodyLocation,
        ),
    ];

    final lifecycle = <LifecycleHook>[];
    if (state != null) {
      for (final name in _lifecycleMethods) {
        final method = _declaredMethod(state.declaration, name);
        if (method == null) continue;
        lifecycle.add(LifecycleHook(
          method: name,
          location: locate(method),
          action: delegates.resolve(
              summarizer.summarize(method.body, isAsync: method.body.isAsynchronous)),
        ));
      }
    }

    final navigation = <NavigationTarget>{};
    final sites = <ActionSite>{};
    final navigationVisitor = _NavigationCollector(detector, navigation, sites);
    for (final declaration in classes) {
      declaration.accept(navigationVisitor);
    }
    for (final interaction in resolvedInteractions) {
      navigation.addAll(interaction.action.navigation);
      sites.addAll(interaction.action.sites);
    }
    for (final hook in lifecycle) {
      navigation.addAll(hook.action.navigation);
      sites.addAll(hook.action.sites);
    }

    return ScreenContextModel(
      name: widget.name,
      filePath: widget.path,
      relativePath: index.relativePath(widget.path),
      importUri: index.importUriFor(widget.path),
      isStateful: state != null,
      stateClassName: state?.name,
      constructors: _constructors(widget.declaration),
      tree: tree.roots,
      treeTruncated: tree.truncated,
      interactions: resolvedInteractions,
      stateFields: state == null ? const [] : _fields(state.declaration),
      dependencies: dependencies,
      navigation: navigation.toList(),
      lifecycle: lifecycle,
      location: locate(widget.declaration),
      sites: sites.toList(),
    );
  }

  static MethodDeclaration? _declaredMethod(ClassDeclaration declaration, String name) {
    for (final member in declaration.members) {
      if (member is MethodDeclaration && member.name.lexeme == name) return member;
    }
    return null;
  }

  static List<ConstructorInfo> _constructors(ClassDeclaration declaration) {
    final fieldTypes = <String, String>{
      for (final field in _fields(declaration)) field.name: field.type,
    };
    final constructors = <ConstructorInfo>[];

    for (final member in declaration.members) {
      if (member is! ConstructorDeclaration || member.factoryKeyword != null) continue;
      final parameters = <ParameterInfo>[];

      for (final parameter in member.parameters.parameters) {
        final base = parameter is DefaultFormalParameter ? parameter.parameter : parameter;
        final name = base.name?.lexeme ?? '';
        String type;
        if (base is SimpleFormalParameter) {
          type = base.type?.toSource() ?? 'dynamic';
        } else if (base is FieldFormalParameter) {
          type = base.type?.toSource() ?? fieldTypes[name] ?? 'dynamic';
        } else if (base is SuperFormalParameter) {
          type = name == 'key' ? 'Key?' : (base.type?.toSource() ?? 'dynamic');
        } else {
          type = 'Function';
        }

        parameters.add(ParameterInfo(
          name: name,
          type: type,
          isRequired: parameter.isRequired,
          isNamed: parameter.isNamed,
          defaultValue: parameter is DefaultFormalParameter
              ? parameter.defaultValue?.toSource()
              : null,
        ));
      }

      constructors.add(ConstructorInfo(
        className: declaration.name.lexeme,
        name: member.name?.lexeme,
        isConst: member.constKeyword != null,
        parameters: parameters,
      ));
    }

    if (constructors.isEmpty) {
      constructors.add(ConstructorInfo(
        className: declaration.name.lexeme,
        isConst: false,
        parameters: const [],
      ));
    }
    return constructors;
  }

  static List<FieldInfo> _fields(ClassDeclaration declaration) {
    final fields = <FieldInfo>[];
    for (final member in declaration.members) {
      if (member is! FieldDeclaration || member.isStatic) continue;
      final list = member.fields;
      for (final variable in list.variables) {
        final initializer = variable.initializer?.toSource();
        fields.add(FieldInfo(
          name: variable.name.lexeme,
          location: locate(variable),
          type: list.type?.toSource() ?? 'var',
          isFinal: list.isFinal || list.isConst,
          initializer: initializer == null || initializer.length > 60
              ? (initializer == null ? null : '${initializer.substring(0, 57)}...')
              : initializer,
        ));
      }
    }
    return fields;
  }
}

/// Follows calls such as `authController.login` into the dependency's own
/// method, so navigation, snackbars and state changes done by a controller
/// are attributed to the screen interaction that triggers them.
class _DelegateResolver {
  _DelegateResolver(this._index, this._detector, this._variableTypes);

  final ProjectIndex _index;
  final NavigationDetector _detector;
  final Map<String, String> _variableTypes;

  ActionSummary resolve(ActionSummary action) {
    final navigation = {...action.navigation};
    final effects = {...action.effects};
    final stateChanges = {...action.stateChanges};
    final sites = {...action.sites};

    for (final call in action.calls) {
      final dot = call.lastIndexOf('.');
      if (dot <= 0) continue;
      final receiver = call.substring(0, dot);
      final member = call.substring(dot + 1);
      final type = _variableTypes[receiver] ?? (isTypeName(receiver) ? receiver : null);
      if (type == null || _index.isWidget(type)) continue;

      final ref = _index.classNamed(type);
      if (ref == null) continue;
      final methods = methodsOf([ref.declaration]);
      final method = methods[member];
      if (method == null) continue;

      final inner = ActionSummarizer(methods: methods, navigation: _detector, maxDepth: 1)
          .summarize(method.body, isAsync: method.body.isAsynchronous);
      navigation.addAll(inner.navigation);
      sites.addAll(inner.sites);
      effects.addAll(inner.effects.map((e) => '$e (in $type.$member)'));
      stateChanges.addAll(inner.stateChanges.map((s) => '$s (in $type)'));
    }

    return ActionSummary(
      calls: action.calls,
      navigation: navigation.toList(),
      stateChanges: stateChanges.toList(),
      effects: effects.toList(),
      isAsync: action.isAsync,
      sites: sites.toList(),
    );
  }
}

class _NavigationCollector extends RecursiveAstVisitor<void> {
  _NavigationCollector(this._detector, this._targets, this._sites);

  final NavigationDetector _detector;
  final Set<NavigationTarget> _targets;
  final Set<ActionSite> _sites;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = _detector.detect(node);
    if (target != null) {
      _targets.add(target);
      final location = locate(node);
      if (location != null) {
        _sites.add(ActionSite(
            kind: SiteKind.navigation, description: target.describe(), location: location));
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// Finds the collaborators a screen uses and which of their members it calls.
///
/// A class counts as a dependency when the screen obtains it explicitly
/// (Get.find, Provider.of, context.read, a singleton `.instance`, a typed
/// builder such as GetBuilder<T>) or when the screen invokes one of its
/// methods. Plain data models whose properties are only read are not listed.
class _DependencyCollector extends RecursiveAstVisitor<void> {
  _DependencyCollector(this._index, this._widget, this._state);

  final ProjectIndex _index;
  final ClassRef _widget;
  final ClassRef? _state;

  final _variableTypes = <String, String>{};

  /// Variable name → class, available after [collect].
  Map<String, String> get variableTypes => Map.unmodifiable(_variableTypes);
  final _acquisitions = <String, Set<String>>{};
  final _methodsUsed = <String, Set<String>>{};
  final _propertiesUsed = <String, Set<String>>{};

  static const _typedBuilders = {
    'GetBuilder',
    'GetX',
    'Consumer',
    'Selector',
    'BlocBuilder',
    'BlocConsumer',
    'BlocListener',
    'BlocSelector',
    'ChangeNotifierProvider',
    'BlocProvider',
  };

  static const _excludedTypes = {'dynamic', 'var', 'InvalidType', 'Object', 'Widget'};

  List<DependencyUsage> collect() {
    final classes = [_widget.declaration, if (_state != null) _state.declaration];

    final superclass = _widget.declaration.extendsClause?.superclass;
    if (superclass != null && superclass.name.lexeme == 'GetView') {
      final typeArgs = superclass.typeArguments?.arguments ?? const [];
      if (typeArgs.isNotEmpty && typeArgs.first is NamedType) {
        final type = (typeArgs.first as NamedType).name.lexeme;
        _variableTypes['controller'] = type;
        _acquire(type, 'GetView<$type>');
      }
    }

    final typeCollector = _VariableTypeCollector(_variableTypes);
    for (final declaration in classes) {
      declaration.accept(typeCollector);
    }
    for (final declaration in classes) {
      declaration.accept(this);
    }

    final types = {..._acquisitions.keys, ..._methodsUsed.keys}
        .where((t) => !_excludedTypes.contains(t))
        .where((t) => t != _widget.name && t != _state?.name && !_index.isWidget(t))
        .where((t) => _acquisitions.containsKey(t) || _index.classNamed(t) != null)
        .toList()
      ..sort();

    return [
      for (final type in types)
        DependencyUsage(
          type: type,
          acquisitions: (_acquisitions[type] ?? const <String>{}).toList()..sort(),
          members: _signatures(type),
          isProjectClass: _index.classNamed(type) != null,
          location: _index.classNamed(type) == null ? null : locate(_index.classNamed(type)!.declaration),
        ),
    ];
  }

  void _acquire(String type, String how) =>
      _acquisitions.putIfAbsent(type, () => {}).add(how);

  void _useMethod(String type, String member) =>
      _methodsUsed.putIfAbsent(type, () => {}).add(member);

  void _useProperty(String type, String member) =>
      _propertiesUsed.putIfAbsent(type, () => {}).add(member);

  /// The dependency type a receiver expression stands for, if any.
  String? _receiverType(Expression? target) {
    if (target == null) return null;
    final node = unwrap(target);
    if (node is SimpleIdentifier) return _variableTypes[node.name];
    if (node is MethodInvocation) {
      final receiver = node.realTarget?.toSource();
      if (receiver == 'Get' && (node.methodName.name == 'find' || node.methodName.name == 'put')) {
        return _typeArgument(node.typeArguments);
      }
      final method = node.methodName.name;
      if ((receiver == 'context' && (method == 'read' || method == 'watch')) ||
          ((receiver == 'Provider' || receiver == 'BlocProvider') && method == 'of')) {
        return _typeArgument(node.typeArguments);
      }
    }
    final singleton = _singletonType(node);
    if (singleton != null) return singleton;
    return null;
  }

  /// `FirebaseAuth.instance` → FirebaseAuth.
  String? _singletonType(Expression node) {
    if (node is PrefixedIdentifier &&
        node.identifier.name == 'instance' &&
        isTypeName(node.prefix.name)) {
      return node.prefix.name;
    }
    if (node is PropertyAccess &&
        node.propertyName.name == 'instance' &&
        node.target is SimpleIdentifier &&
        isTypeName((node.target as SimpleIdentifier).name)) {
      return (node.target as SimpleIdentifier).name;
    }
    return null;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final receiver = node.realTarget?.toSource();
    final typeArg = _typeArgument(node.typeArguments);

    if (receiver == 'Get' && const {'find', 'put', 'lazyPut', 'putAsync'}.contains(method)) {
      final type = typeArg ??
          (method == 'put' && node.argumentList.arguments.isNotEmpty
              ? asWidgetCall(node.argumentList.arguments.first)?.type
              : null);
      if (type != null) _acquire(type, 'Get.$method');
    } else if ((receiver == 'Provider' ||
            receiver == 'BlocProvider' ||
            receiver == 'RepositoryProvider') &&
        method == 'of' &&
        typeArg != null) {
      _acquire(typeArg, '$receiver.of');
    } else if (receiver == 'context' &&
        const {'read', 'watch', 'select'}.contains(method) &&
        typeArg != null) {
      _acquire(typeArg, 'context.$method');
    } else if (receiver == 'ref' &&
        const {'watch', 'read', 'listen'}.contains(method) &&
        node.argumentList.arguments.isNotEmpty) {
      _acquire(node.argumentList.arguments.first.toSource(), 'ref.$method');
    }

    final call = asWidgetCall(node);
    if (call != null) _typedBuilder(call);

    final type = _receiverType(node.realTarget);
    if (type != null) {
      _useMethod(type, method);
      final singleton = node.realTarget == null ? null : _singletonType(unwrap(node.realTarget!));
      if (singleton != null) _acquire(singleton, 'singleton .instance');
    }

    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final call = asWidgetCall(node);
    if (call != null) _typedBuilder(call);
    super.visitInstanceCreationExpression(node);
  }

  void _typedBuilder(WidgetCall call) {
    if (!_typedBuilders.contains(call.type)) return;
    final type = call.typeArgument(0);
    if (type != null) _acquire(type, '${call.type}<$type>');
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final type = _variableTypes[node.prefix.name];
    if (type != null) _useProperty(type, node.identifier.name);
    final singleton = _singletonType(node);
    if (singleton != null) _acquire(singleton, 'singleton .instance');
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final type = _receiverType(node.realTarget);
    if (type != null) _useProperty(type, node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  List<MemberInfo> _signatures(String type) {
    final ref = _index.classNamed(type);
    final methods = (_methodsUsed[type] ?? const <String>{}).toList()..sort();
    final properties = (_propertiesUsed[type] ?? const <String>{})
        .where((p) => !methods.contains(p))
        .toList()
      ..sort();

    MemberInfo? declared(String name) {
      if (ref == null) return null;
      MemberInfo info(String signature, AstNode node) =>
          MemberInfo(name: name, signature: signature, location: locate(node));
      for (final member in ref.declaration.members) {
        if (member is MethodDeclaration && member.name.lexeme == name) {
          final returnType = member.returnType?.toSource() ?? 'dynamic';
          if (member.isGetter) return info('$returnType get $name', member);
          final params = member.parameters?.toSource() ?? '()';
          final asyncMarker = member.body.isAsynchronous ? ' async' : '';
          return info('$returnType $name$params$asyncMarker', member);
        }
        if (member is FieldDeclaration) {
          for (final variable in member.fields.variables) {
            if (variable.name.lexeme == name) {
              final fieldType = member.fields.type?.toSource();
              if (fieldType != null) return info('$fieldType $name', variable);
              final init = variable.initializer?.toSource() ?? '';
              return info(
                  'var $name${init.isEmpty ? '' : ' = ${init.length > 40 ? '${init.substring(0, 37)}...' : init}'}',
                  variable);
            }
          }
        }
      }
      return null;
    }

    return [
      for (final m in methods) declared(m) ?? MemberInfo(name: m, signature: '$m(...)'),
      for (final p in properties) declared(p) ?? MemberInfo(name: p, signature: p),
    ];
  }

  static String? _typeArgument(TypeArgumentList? arguments) {
    final first = arguments?.arguments.firstOrNull;
    if (first == null) return null;
    return first is NamedType ? first.name.lexeme : first.toSource();
  }
}

/// Maps field and local variable names to the class they hold.
class _VariableTypeCollector extends RecursiveAstVisitor<void> {
  _VariableTypeCollector(this._types);

  final Map<String, String> _types;

  @override
  void visitVariableDeclarationList(VariableDeclarationList node) {
    final declared = node.type;
    for (final variable in node.variables) {
      final name = variable.name.lexeme;
      String? type;
      if (declared is NamedType) {
        type = declared.name.lexeme;
      } else if (variable.initializer != null) {
        type = _inferred(variable.initializer!);
      }
      if (type != null && type != 'dynamic') _types.putIfAbsent(name, () => type!);
    }
    super.visitVariableDeclarationList(node);
  }

  /// Builder → (closure parameter index, type argument index) of the value
  /// the builder hands to its closure, e.g. `GetBuilder<C>(builder: (c) {})`.
  static const _builderParameters = {
    'GetBuilder': (0, 0),
    'GetX': (0, 0),
    'Consumer': (1, 0),
    'BlocBuilder': (1, 1),
    'BlocConsumer': (1, 1),
    'BlocListener': (1, 1),
  };

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final call = asWidgetCall(node);
    if (call != null) _builderParameter(call);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final call = asWidgetCall(node);
    if (call != null) _builderParameter(call);
    super.visitInstanceCreationExpression(node);
  }

  void _builderParameter(WidgetCall call) {
    final slot = _builderParameters[call.type];
    if (slot == null) return;
    final (parameterIndex, typeIndex) = slot;
    final type = call.typeArgument(typeIndex);
    if (type == null) return;
    for (final name in const ['builder', 'listener']) {
      final closure = call.named(name);
      final function = closure == null ? null : unwrap(closure);
      if (function is! FunctionExpression) continue;
      final parameters = function.parameters?.parameters ?? const <FormalParameter>[];
      if (parameterIndex >= parameters.length) continue;
      final parameterName = parameters[parameterIndex].name?.lexeme;
      if (parameterName != null && parameterName != '_') {
        _types.putIfAbsent(parameterName, () => type);
      }
    }
  }

  static String? _inferred(Expression initializer) {
    var node = unwrap(initializer);
    if (node is AwaitExpression) node = unwrap(node.expression);
    if (node is MethodInvocation) {
      final receiver = node.realTarget?.toSource();
      final typeArgs = node.typeArguments?.arguments ?? const [];
      final typeArg = typeArgs.isEmpty
          ? null
          : (typeArgs.first is NamedType
              ? (typeArgs.first as NamedType).name.lexeme
              : typeArgs.first.toSource());
      if (receiver == 'Get' && node.methodName.name == 'put' && typeArg == null) {
        final first = node.argumentList.arguments.firstOrNull;
        return first == null ? null : asWidgetCall(first)?.type;
      }
      if (typeArg != null &&
          (receiver == 'Get' ||
              receiver == 'Provider' ||
              receiver == 'BlocProvider' ||
              receiver == 'context')) {
        return typeArg;
      }
    }
    return asWidgetCall(node)?.type;
  }
}
