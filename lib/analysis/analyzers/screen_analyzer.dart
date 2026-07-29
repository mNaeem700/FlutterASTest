import '../models/widget_model.dart';
import '../models/screen_model.dart';

class ScreenAnalyzer {
  const ScreenAnalyzer();

  List<ScreenModel> analyse(List<WidgetModel> widgets) {
    final List<ScreenModel> screens = [];

    for (final widget in widgets) {
      // Sprint 4.3 Heuristic: Check if the name ends with Screen, Page, or View
      if (widget.name.endsWith('Screen') ||
          widget.name.endsWith('Page') ||
          widget.name.endsWith('View')) {
        // Map the boolean flags from Sprint 4.2 to the WidgetType enum
        final type =
            widget.isStateful ? WidgetType.stateful : WidgetType.stateless;

        screens.add(
          ScreenModel(
            name: widget.name,
            filePath: widget.filePath,
            widgetType: type,
          ),
        );
      }
    }

    return List.unmodifiable(screens);
  }
}
