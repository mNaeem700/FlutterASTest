import 'package:meta/meta.dart';

@immutable
class WidgetEdge {
  const WidgetEdge({
    required this.parent,
    required this.child,
  });

  final String parent;
  final String child;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetEdge &&
          runtimeType == other.runtimeType &&
          parent == other.parent &&
          child == other.child;

  @override
  int get hashCode => parent.hashCode ^ child.hashCode;
}
