import '../flutter_ast/widget_call.dart';
import '../flutter_ast/widget_tree_extractor.dart';
import '../models/screen_context_model.dart';
import '../models/screen_model.dart';
import '../models/widget_model.dart';
import '../project_index.dart';

/// Identifies which widgets are screens using structural evidence: the widget
/// builds a Scaffold, or another class navigates to it. Name suffixes alone
/// (…Screen, …Page) are not enough, because reusable widgets use them too.
class ScreenAnalyzer {
  const ScreenAnalyzer();

  static const _appShells = {
    'MaterialApp',
    'MaterialApp.router',
    'GetMaterialApp',
    'GetMaterialApp.router',
    'CupertinoApp',
    'CupertinoApp.router',
  };

  List<ScreenModel> analyse(
    ProjectIndex index,
    List<WidgetModel> widgets, {
    required Set<String> navigationTargets,
  }) {
    final screens = <ScreenModel>[];

    for (final widget in widgets) {
      final reasons = <String>[];
      final isNavigationTarget = navigationTargets.contains(widget.name);
      final roots = _buildTree(index, widget.name);

      final isAppShell = roots.any((r) => _appShells.contains(r.type));
      final buildsScaffold = !isAppShell &&
          roots.any((root) => [root, ...root.descendants]
              .any((node) => node.type.split('.').first.endsWith('Scaffold')));

      if (buildsScaffold) reasons.add('builds a Scaffold');
      if (isNavigationTarget) reasons.add('navigation target');
      if (reasons.isEmpty) continue;

      screens.add(ScreenModel(
        name: widget.name,
        filePath: widget.filePath,
        widgetType: widget.isStateful ? WidgetType.stateful : WidgetType.stateless,
        detectedBy: reasons,
      ));
    }

    return List.unmodifiable(screens);
  }

  List<WidgetTreeNode> _buildTree(ProjectIndex index, String widgetName) {
    final widget = index.widgetClasses[widgetName];
    if (widget == null) return const [];
    final state = index.stateClassOf[widgetName];
    final methods = methodsOf([
      if (state != null) state.declaration,
      widget.declaration,
    ]);
    final build = methods['build'];
    if (build == null) return const [];
    return WidgetTreeExtractor(methods: methods, maxNodes: 200).extract(build).roots;
  }
}
