import 'package:meta/meta.dart';

@immutable
class NavigationEdge {
  const NavigationEdge({
    required this.fromScreen,
    required this.toScreen,
    required this.navigationType,
  });

  final String fromScreen;
  final String toScreen;
  final NavigationType navigationType;
}

enum NavigationType {
  push,
  pushReplacement,
  pushNamed,
  popAndPushNamed,
  go,
  replace,
}
