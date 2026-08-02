import 'package:flutterastest/analysis/analysis_result.dart';
import 'package:flutterastest/analysis/models/state_model.dart';
import 'package:flutterastest/pkg/models/knowledge_graph.dart';
import 'package:flutterastest/pkg/models/pkg_edge.dart';
import 'package:flutterastest/pkg/models/pkg_node.dart';

class PkgBuilder {
  KnowledgeGraph build(AnalysisResult analysis) {
    final graph = KnowledgeGraph();

    // 1. Add Screens
    for (final screen in analysis.screens) {
      final name = _safelyExtractName(screen);
      graph.addNode(PkgNode(id: name, label: name, type: NodeType.screen));
    }

    // 2. Add State & Variables (The 'owns' relationship)
    for (final stateObj in analysis.states) {
      if (stateObj is StateModel) {
        final ctrlName = stateObj.className;
        graph.addNode(
            PkgNode(id: ctrlName, label: ctrlName, type: NodeType.controller));

        for (final variable in stateObj.variables) {
          final varId = '${ctrlName}_${variable.name}';
          graph.addNode(PkgNode(
              id: varId, label: variable.name, type: NodeType.variable));
          graph.addEdge(PkgEdge(
              sourceId: ctrlName, targetId: varId, type: EdgeType.owns));
        }
      }
    }

    // 3. Add Dependencies (The 'uses' relationship)
    for (final dep in analysis.dependencies) {
      final depStr = dep.toString();
      // Basic extraction logic assuming format like DependencyEdge(source: ScreenA, target: AuthController)
      final parts = depStr.replaceAll(RegExp(r'[^a-zA-Z0-9_ ]'), '').split(' ');

      String? source;
      String? target;

      // Simple heuristic for mapping
      for (final part in parts) {
        if (graph.getNode(part) != null &&
            graph.getNode(part)!.type == NodeType.screen) {
          source = part;
        } else if (part.contains('Controller') ||
            part.contains('Repo') ||
            part.contains('Service')) {
          target = part;
          NodeType type = NodeType.controller;
          if (part.contains('Repo')) type = NodeType.repository;
          if (part.contains('Service')) type = NodeType.service;

          graph.addNode(PkgNode(id: target, label: target, type: type));
        }
      }

      if (source != null && target != null) {
        graph.addEdge(
            PkgEdge(sourceId: source, targetId: target, type: EdgeType.uses));
      }
    }

    // 4. Add Callbacks (The 'calls' and 'navigates' relationships)
    for (final cb in analysis.callbacks) {
      final widgetId = cb.widgetName;
      final methodId = cb.invokedMethod;

      graph.addNode(
          PkgNode(id: widgetId, label: widgetId, type: NodeType.widget));
      graph.addNode(
          PkgNode(id: methodId, label: methodId, type: NodeType.callback));

      // Widget -> calls -> Method
      graph.addEdge(PkgEdge(
          sourceId: widgetId, targetId: methodId, type: EdgeType.calls));

      // If it's a navigation callback
      if (cb.isNavigation) {
        final targetScreen = cb.targetScreen ?? cb.route ?? 'UnknownScreen';
        graph.addNode(PkgNode(
            id: targetScreen, label: targetScreen, type: NodeType.screen));
        graph.addEdge(PkgEdge(
            sourceId: methodId,
            targetId: targetScreen,
            type: EdgeType.navigates));
      }
    }

    // 5. Add Widget Tree (The 'contains' relationship)
    for (final edge in analysis.hierarchy) {
      try {
        final parent = (edge as dynamic).parent.toString();
        final child = (edge as dynamic).child.toString();

        if (parent != 'null' &&
            child != 'null' &&
            !child.contains('Instance of')) {
          graph.addNode(
              PkgNode(id: parent, label: parent, type: NodeType.widget));
          graph
              .addNode(PkgNode(id: child, label: child, type: NodeType.widget));
          graph.addEdge(PkgEdge(
              sourceId: parent, targetId: child, type: EdgeType.contains));
        }
      } catch (_) {}
    }

    return graph;
  }

  String _safelyExtractName(dynamic obj) {
    try {
      return obj.name ?? obj.className ?? obj.toString();
    } catch (_) {
      return obj.toString();
    }
  }
}
