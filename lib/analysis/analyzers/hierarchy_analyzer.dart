import '../flutter_ast/widget_call.dart';
import '../flutter_ast/widget_tree_extractor.dart';
import '../models/screen_context_model.dart';
import '../models/widget_edge.dart';
import '../project_index.dart';

/// Parent → child widget edges from every widget's build() tree, including an
/// edge from the widget class to each root it returns.
class HierarchyAnalyzer {
  const HierarchyAnalyzer();

  List<WidgetEdge> analyse(ProjectIndex index) {
    final edges = <WidgetEdge>{};

    for (final widget in index.widgetClasses.values) {
      final state = index.stateClassOf[widget.name];
      final methods = methodsOf([
        if (state != null) state.declaration,
        widget.declaration,
      ]);
      final build = methods['build'];
      if (build == null) continue;

      final roots = WidgetTreeExtractor(methods: methods, maxNodes: 500).extract(build).roots;
      void walk(WidgetTreeNode node) {
        for (final child in node.children) {
          edges.add(WidgetEdge(parent: node.type, child: child.type));
          walk(child);
        }
      }

      for (final root in roots) {
        edges.add(WidgetEdge(parent: widget.name, child: root.type));
        walk(root);
      }
    }

    return edges.toList();
  }
}
