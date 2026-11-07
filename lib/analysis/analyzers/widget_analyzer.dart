import '../models/widget_model.dart';
import '../project_index.dart';

class WidgetAnalyzer {
  const WidgetAnalyzer();

  List<WidgetModel> analyse(ProjectIndex index) {
    final widgets = [
      for (final ref in index.widgetClasses.values)
        WidgetModel(
          name: ref.name,
          filePath: ref.path,
          isStateful: index.stateClassOf.containsKey(ref.name),
          isStateless: !index.stateClassOf.containsKey(ref.name),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return widgets;
  }
}
