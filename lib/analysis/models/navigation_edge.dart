import 'package:meta/meta.dart';

import 'screen_context_model.dart';

@immutable
class NavigationEdge {
  const NavigationEdge({
    required this.fromScreen,
    required this.toScreen,
    required this.api,
    required this.kind,
    required this.isRouteName,
  });

  /// Class containing the navigation call (a widget, its State, or a controller).
  final String fromScreen;

  /// Destination widget class, or a route name when [isRouteName] is true.
  final String toScreen;

  /// e.g. "Navigator.push", "Get.offAll", "context.go".
  final String api;
  final NavigationKind kind;
  final bool isRouteName;

  @override
  bool operator ==(Object other) =>
      other is NavigationEdge &&
      other.fromScreen == fromScreen &&
      other.toScreen == toScreen &&
      other.api == api;

  @override
  int get hashCode => Object.hash(fromScreen, toScreen, api);
}
