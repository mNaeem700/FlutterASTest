import 'package:meta/meta.dart';

// Note: If you already defined WidgetType in widget_model.dart,
// you can import it instead of defining it here.
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
  });

  final String name;
  final String filePath;
  final WidgetType widgetType;
}
