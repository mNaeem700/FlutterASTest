import 'package:meta/meta.dart';

import 'source_location.dart';

export 'source_location.dart';

/// One widget in a screen's build() tree.
@immutable
class WidgetTreeNode {
  const WidgetTreeNode({
    required this.path,
    required this.type,
    this.labels = const [],
    this.key,
    this.handlers = const [],
    this.children = const [],
    this.location,
    this.validations = const [],
  });

  /// Position in the tree, e.g. "0.1.2". Unique within one screen.
  final String path;

  /// Widget type, including a named constructor when present (ListView.builder).
  final String type;

  /// Literal texts, hints and icons a test can find.
  final List<String> labels;
  final String? key;

  /// Event handler argument names on this widget, e.g. onPressed.
  final List<String> handlers;
  final List<WidgetTreeNode> children;

  /// The constructor call that creates the widget.
  final SourceLocation? location;

  /// Error messages of the `validator` argument, or `by <function>` when the
  /// messages live outside the project's visible code.
  final List<String> validations;

  Iterable<WidgetTreeNode> get descendants sync* {
    for (final child in children) {
      yield child;
      yield* child.descendants;
    }
  }

  /// The first label in this subtree, used to describe buttons by their text.
  String? get firstLabel {
    if (labels.isNotEmpty) return labels.first;
    for (final node in descendants) {
      if (node.labels.isNotEmpty) return node.labels.first;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'type': type,
        if (labels.isNotEmpty) 'labels': labels,
        if (key != null) 'key': key,
        if (handlers.isNotEmpty) 'handlers': handlers,
        if (location != null) 'location': location!.toJson(),
        if (validations.isNotEmpty) 'validations': validations,
        if (children.isNotEmpty) 'children': children.map((c) => c.toJson()).toList(),
      };
}

enum NavigationKind { push, replace, clearStack, pop }

@immutable
class NavigationTarget {
  const NavigationTarget({
    required this.api,
    required this.kind,
    this.target,
    this.isRouteName = false,
  });

  /// The call that navigates, e.g. "Navigator.push", "Get.to", "context.go".
  final String api;
  final NavigationKind kind;

  /// Destination widget class or route name; null for pops.
  final String? target;
  final bool isRouteName;

  String describe() {
    if (target == null) return api;
    return isRouteName ? '$api("$target")' : '$api → $target';
  }

  @override
  bool operator ==(Object other) =>
      other is NavigationTarget &&
      other.api == api &&
      other.kind == kind &&
      other.target == target &&
      other.isRouteName == isRouteName;

  @override
  int get hashCode => Object.hash(api, kind, target, isRouteName);

  Map<String, dynamic> toJson() => {
        'api': api,
        'kind': kind.name,
        'target': target,
        'isRouteName': isRouteName,
      };
}

enum SiteKind { navigation, stateChange, effect }

/// A statement that navigates, changes state or starts a UI effect, at the
/// place in the source where it happens (possibly in a controller file).
/// Used for navigation and state coverage.
@immutable
class ActionSite {
  const ActionSite({required this.kind, required this.description, required this.location});

  final SiteKind kind;
  final String description;
  final SourceLocation location;

  @override
  bool operator ==(Object other) =>
      other is ActionSite && other.kind == kind && other.location == location;

  @override
  int get hashCode => Object.hash(kind, location);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'description': description,
        'location': location.toJson(),
      };
}

/// What a callback or lifecycle method does, as far as static analysis shows.
@immutable
class ActionSummary {
  const ActionSummary({
    this.calls = const [],
    this.navigation = const [],
    this.stateChanges = const [],
    this.effects = const [],
    this.isAsync = false,
    this.sites = const [],
    this.events = const [],
  });

  /// Invoked members, e.g. "authController.login", "_validate".
  final List<String> calls;
  final List<NavigationTarget> navigation;

  /// How state changes: "setState", "Rx .value", "update()".
  final List<String> stateChanges;

  /// UI side effects: dialogs, snackbars, timers.
  final List<String> effects;
  final bool isAsync;

  /// Where the navigation, state changes and effects happen.
  final List<ActionSite> sites;

  /// Events added to a Bloc, as `receiver|EventClass`.
  final List<String> events;

  bool get isEmpty =>
      calls.isEmpty && navigation.isEmpty && stateChanges.isEmpty && effects.isEmpty;

  Map<String, dynamic> toJson() => {
        'calls': calls,
        'navigation': navigation.map((n) => n.toJson()).toList(),
        'stateChanges': stateChanges,
        'effects': effects,
        'isAsync': isAsync,
        'sites': sites.map((s) => s.toJson()).toList(),
        if (events.isNotEmpty) 'events': events,
      };
}

/// A user interaction: one event handler on one widget.
@immutable
class InteractionModel {
  const InteractionModel({
    required this.widgetPath,
    required this.widgetType,
    required this.event,
    required this.action,
    this.label,
    this.key,
    this.location,
    this.bodyLocation,
  });

  final String widgetPath;
  final String widgetType;
  final String event;
  final String? label;
  final String? key;
  final ActionSummary action;

  /// The handler argument expression.
  final SourceLocation? location;

  /// The code that runs when the event fires (closure body or the method a
  /// tear-off refers to); null when it does nothing.
  final SourceLocation? bodyLocation;

  Map<String, dynamic> toJson() => {
        'widgetPath': widgetPath,
        'widgetType': widgetType,
        'event': event,
        'label': label,
        'key': key,
        if (location != null) 'location': location!.toJson(),
        if (bodyLocation != null) 'bodyLocation': bodyLocation!.toJson(),
        'action': action.toJson(),
      };
}

@immutable
class ParameterInfo {
  const ParameterInfo({
    required this.name,
    required this.type,
    required this.isRequired,
    required this.isNamed,
    this.defaultValue,
  });

  final String name;
  final String type;
  final bool isRequired;
  final bool isNamed;
  final String? defaultValue;

  String render() {
    final buffer = StringBuffer();
    if (isRequired && isNamed) buffer.write('required ');
    buffer.write('$type $name');
    if (defaultValue != null) buffer.write(' = $defaultValue');
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'isRequired': isRequired,
        'isNamed': isNamed,
        'defaultValue': defaultValue,
      };
}

@immutable
class ConstructorInfo {
  const ConstructorInfo({
    required this.className,
    required this.isConst,
    required this.parameters,
    this.name,
  });

  final String className;
  final String? name;
  final bool isConst;
  final List<ParameterInfo> parameters;

  String render() {
    final positional = parameters.where((p) => !p.isNamed).map((p) => p.render());
    final named = parameters.where((p) => p.isNamed).map((p) => p.render());
    final parts = [
      ...positional,
      if (named.isNotEmpty) '{${named.join(', ')}}',
    ];
    final title = name == null ? className : '$className.$name';
    return '${isConst ? 'const ' : ''}$title(${parts.join(', ')})';
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        'name': name,
        'isConst': isConst,
        'parameters': parameters.map((p) => p.toJson()).toList(),
      };
}

@immutable
class FieldInfo {
  const FieldInfo({
    required this.name,
    required this.type,
    required this.isFinal,
    this.initializer,
    this.location,
  });

  final String name;
  final String type;
  final bool isFinal;
  final String? initializer;
  final SourceLocation? location;

  String render() {
    final head = '${isFinal ? 'final ' : ''}$type $name';
    return initializer == null ? head : '$head = $initializer';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'isFinal': isFinal,
        'initializer': initializer,
        if (location != null) 'location': location!.toJson(),
      };
}

/// A member of a dependency that the screen uses.
@immutable
class MemberInfo {
  const MemberInfo({required this.name, required this.signature, this.location});

  final String name;

  /// Declaration signature, e.g. "Future<void> login(String email) async".
  final String signature;

  /// Where the member is declared; null for members of external classes.
  final SourceLocation? location;

  Map<String, dynamic> toJson() => {
        'name': name,
        'signature': signature,
        if (location != null) 'location': location!.toJson(),
      };
}

/// A class the screen depends on and the members it actually uses.
@immutable
class DependencyUsage {
  const DependencyUsage({
    required this.type,
    required this.acquisitions,
    required this.members,
    required this.isProjectClass,
    this.location,
    this.importUri,
    this.constructors = const [],
  });

  final String type;

  /// How the screen obtains it: "Get.find", "Provider.of", "field", "singleton".
  final List<String> acquisitions;

  /// Members used by the screen.
  final List<MemberInfo> members;
  final bool isProjectClass;

  /// The class declaration; null for external classes.
  final SourceLocation? location;

  /// Lets a test import the class to register or fake it.
  final String? importUri;
  final List<String> constructors;

  Map<String, dynamic> toJson() => {
        'type': type,
        'acquisitions': acquisitions,
        'members': members.map((m) => m.toJson()).toList(),
        'isProjectClass': isProjectClass,
        if (importUri != null) 'importUri': importUri,
        if (constructors.isNotEmpty) 'constructors': constructors,
        if (location != null) 'location': location!.toJson(),
      };
}

@immutable
class LifecycleHook {
  const LifecycleHook({required this.method, required this.action, this.location});

  final String method;
  final ActionSummary action;
  final SourceLocation? location;

  Map<String, dynamic> toJson() => {
        'method': method,
        if (location != null) 'location': location!.toJson(),
        'action': action.toJson(),
      };
}

/// Everything static analysis knows about one screen.
@immutable
class ScreenContextModel {
  const ScreenContextModel({
    required this.name,
    required this.filePath,
    required this.relativePath,
    required this.importUri,
    required this.isStateful,
    required this.stateClassName,
    required this.constructors,
    required this.tree,
    required this.treeTruncated,
    required this.interactions,
    required this.stateFields,
    required this.dependencies,
    required this.navigation,
    required this.lifecycle,
    this.location,
    this.sites = const [],
  });

  final String name;
  final String filePath;
  final String relativePath;
  final String? importUri;
  final bool isStateful;
  final String? stateClassName;
  final List<ConstructorInfo> constructors;

  /// Roots returned by build(). More than one when build() has several returns.
  final List<WidgetTreeNode> tree;
  final bool treeTruncated;
  final List<InteractionModel> interactions;
  final List<FieldInfo> stateFields;
  final List<DependencyUsage> dependencies;

  /// Every navigation the screen's classes can trigger.
  final List<NavigationTarget> navigation;
  final List<LifecycleHook> lifecycle;

  /// The widget class declaration.
  final SourceLocation? location;

  /// Every navigation, state change and effect site reachable from the
  /// screen: its own classes plus controller methods its interactions call.
  final List<ActionSite> sites;

  Iterable<WidgetTreeNode> get allWidgets sync* {
    for (final root in tree) {
      yield root;
      yield* root.descendants;
    }
  }

  int get widgetCount => allWidgets.length;

  Map<String, dynamic> toJson() => {
        'name': name,
        'filePath': relativePath,
        'importUri': importUri,
        'isStateful': isStateful,
        'stateClassName': stateClassName,
        if (location != null) 'location': location!.toJson(),
        'constructors': constructors.map((c) => c.toJson()).toList(),
        'tree': tree.map((t) => t.toJson()).toList(),
        'treeTruncated': treeTruncated,
        'interactions': interactions.map((i) => i.toJson()).toList(),
        'stateFields': stateFields.map((f) => f.toJson()).toList(),
        'dependencies': dependencies.map((d) => d.toJson()).toList(),
        'navigation': navigation.map((n) => n.toJson()).toList(),
        'lifecycle': lifecycle.map((l) => l.toJson()).toList(),
        'sites': sites.map((s) => s.toJson()).toList(),
      };
}
