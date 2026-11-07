import 'package:meta/meta.dart';

enum WidgetType {
  stateless,
  stateful,
}

@immutable
class ScreenModel {
  const ScreenModel({
    required this.name,
    required this.filePath,
    required this.widgetType,
    this.detectedBy = const [],
  });

  final String name;
  final String filePath;
  final WidgetType widgetType;

  /// Structural evidence that made this widget a screen, e.g.
  /// "builds a Scaffold", "navigation target".
  final List<String> detectedBy;
}
