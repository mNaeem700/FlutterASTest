import 'package:flutterastest/analysis/analysis_result.dart';
import 'package:flutterastest/analysis/models/screen_context_model.dart';
import 'package:flutterastest/pkg/models/knowledge_graph.dart';
import 'package:flutterastest/pkg/models/pkg_edge.dart';
import 'package:flutterastest/pkg/models/pkg_node.dart';

/// Builds the Program Knowledge Graph from per-screen analysis results.
///
/// Node ids follow Doc 9.19.1: `Package::File::Entity::SourceOffset`, so the
/// same project always yields the same graph. A helper inlined at two tree
/// positions has one source offset, so tree entities include their tree path.
/// Dependency nodes are shared between screens that use the same class.
class PkgBuilder {
  static const _external = '<external>';
  static const _routes = '<routes>';

  late String _package;

  String _id(String file, String entity, int offset) => '$_package::$file::$entity::$offset';

  String _located(SourceLocation? location, String fallbackFile, String entity) =>
      _id(location?.file ?? fallbackFile, entity, location?.offset ?? 0);

  KnowledgeGraph build(AnalysisResult analysis) {
    _package = analysis.projectInfo.packageName;
    final graph = KnowledgeGraph();
    final screenIds = <String, String>{};

    for (final screen in analysis.screenContexts) {
      final id = _located(screen.location, screen.relativePath, screen.name);
      screenIds[screen.name] = id;
      graph.addNode(PkgNode(
        id: id,
        label: screen.name,
        type: NodeType.screen,
        properties: {
          'filePath': screen.relativePath,
          'importUri': screen.importUri,
          'isStateful': screen.isStateful,
          'stateClass': screen.stateClassName,
          'constructors': [for (final c in screen.constructors) c.render()],
          'widgetCount': screen.widgetCount,
          'treeTruncated': screen.treeTruncated,
        },
      ));
    }

    for (final screen in analysis.screenContexts) {
      final id = screenIds[screen.name]!;
      final widgetIds = _addTree(graph, id, screen);
      _addState(graph, id, screen);
      final memberIds = _addDependencies(graph, id, screen);
      _addInteractions(graph, screen, widgetIds, memberIds, screenIds);
      _addLifecycle(graph, id, screen, memberIds, screenIds);
      for (final navigation in screen.navigation) {
        _addNavigation(graph, id, navigation, screenIds);
      }
    }
    return graph;
  }

  Map<String, String> _addTree(KnowledgeGraph graph, String screenId, ScreenContextModel screen) {
    final ids = <String, String>{};
    void add(WidgetTreeNode node, String parentId, int order) {
      final id =
          _located(node.location, screen.relativePath, '${screen.name}/${node.type}@${node.path}');
      ids[node.path] = id;
      graph.addNode(PkgNode(
        id: id,
        label: node.type,
        type: NodeType.widget,
        properties: {
          if (node.labels.isNotEmpty) 'labels': node.labels,
          if (node.key != null) 'key': node.key,
        },
      ));
      graph.addEdge(PkgEdge(sourceId: parentId, targetId: id, type: EdgeType.contains, order: order));
      for (var i = 0; i < node.children.length; i++) {
        add(node.children[i], id, i);
      }
    }

    for (var i = 0; i < screen.tree.length; i++) {
      add(screen.tree[i], screenId, i);
    }
    return ids;
  }

  void _addState(KnowledgeGraph graph, String screenId, ScreenContextModel screen) {
    for (var i = 0; i < screen.stateFields.length; i++) {
      final field = screen.stateFields[i];
      final id = _located(field.location, screen.relativePath, '${screen.name}.${field.name}');
      graph.addNode(PkgNode(
        id: id,
        label: field.name,
        type: NodeType.stateField,
        properties: {'declaration': field.render()},
      ));
      graph.addEdge(PkgEdge(sourceId: screenId, targetId: id, type: EdgeType.bindsState, order: i));
    }
  }

  /// Returns member name → member node ids, for linking calls.
  Map<String, List<String>> _addDependencies(
      KnowledgeGraph graph, String screenId, ScreenContextModel screen) {
    final memberIds = <String, List<String>>{};

    for (var i = 0; i < screen.dependencies.length; i++) {
      final dependency = screen.dependencies[i];
      final id = _located(dependency.location, _external, dependency.type);
      graph.addNode(PkgNode(
        id: id,
        label: dependency.type,
        type: NodeType.dependency,
        properties: {'isProjectClass': dependency.isProjectClass},
      ));
      graph.addEdge(PkgEdge(
        sourceId: screenId,
        targetId: id,
        type: EdgeType.dependsOn,
        order: i,
        label: dependency.acquisitions.join(', '),
      ));

      for (var j = 0; j < dependency.members.length; j++) {
        final member = dependency.members[j];
        final memberId = _located(member.location, _external, '${dependency.type}.${member.name}');
        graph.addNode(PkgNode(
          id: memberId,
          label: member.name,
          type: NodeType.member,
          properties: {'signature': member.signature},
        ));
        graph.addEdge(PkgEdge(sourceId: id, targetId: memberId, type: EdgeType.declares));
        graph.addEdge(PkgEdge(sourceId: screenId, targetId: memberId, type: EdgeType.uses, order: j));
        memberIds.putIfAbsent(member.name, () => []).add(memberId);
      }
    }
    return memberIds;
  }

  void _addInteractions(
    KnowledgeGraph graph,
    ScreenContextModel screen,
    Map<String, String> widgetIds,
    Map<String, List<String>> memberIds,
    Map<String, String> screenIds,
  ) {
    for (final interaction in screen.interactions) {
      final widgetId = widgetIds[interaction.widgetPath];
      if (widgetId == null) continue;
      final id = _located(interaction.location, screen.relativePath,
          '${screen.name}/${interaction.widgetType}@${interaction.widgetPath}.${interaction.event}');
      graph.addNode(PkgNode(
        id: id,
        label: interaction.event,
        type: NodeType.interaction,
        properties: _actionProperties(interaction.action),
      ));
      graph.addEdge(PkgEdge(sourceId: widgetId, targetId: id, type: EdgeType.triggers));
      _linkAction(graph, id, interaction.action, memberIds, screenIds);
    }
  }

  void _addLifecycle(
    KnowledgeGraph graph,
    String screenId,
    ScreenContextModel screen,
    Map<String, List<String>> memberIds,
    Map<String, String> screenIds,
  ) {
    for (var i = 0; i < screen.lifecycle.length; i++) {
      final hook = screen.lifecycle[i];
      final id = _located(hook.location, screen.relativePath, '${screen.name}.${hook.method}');
      graph.addNode(PkgNode(
        id: id,
        label: hook.method,
        type: NodeType.lifecycle,
        properties: _actionProperties(hook.action),
      ));
      graph.addEdge(PkgEdge(sourceId: screenId, targetId: id, type: EdgeType.hasLifecycle, order: i));
      _linkAction(graph, id, hook.action, memberIds, screenIds);
    }
  }

  void _linkAction(
    KnowledgeGraph graph,
    String sourceId,
    ActionSummary action,
    Map<String, List<String>> memberIds,
    Map<String, String> screenIds,
  ) {
    for (final call in action.calls) {
      final name = call.substring(call.lastIndexOf('.') + 1);
      for (final memberId in memberIds[name] ?? const <String>[]) {
        graph.addEdge(PkgEdge(sourceId: sourceId, targetId: memberId, type: EdgeType.calls));
      }
    }
    for (final navigation in action.navigation) {
      _addNavigation(graph, sourceId, navigation, screenIds);
    }
  }

  void _addNavigation(KnowledgeGraph graph, String sourceId, NavigationTarget navigation,
      Map<String, String> screenIds) {
    final target = navigation.target;
    String targetId;
    if (target == null) {
      targetId = _id(_routes, '<previous>', 0);
      graph.addNode(PkgNode(
        id: targetId,
        label: 'previous route',
        type: NodeType.route,
        properties: const {'isPrevious': true},
      ));
    } else if (!navigation.isRouteName && screenIds.containsKey(target)) {
      targetId = screenIds[target]!;
    } else {
      targetId = _id(_routes, target, 0);
      graph.addNode(PkgNode(
        id: targetId,
        label: target,
        type: NodeType.route,
        properties: {'isRouteName': navigation.isRouteName},
      ));
    }
    graph.addEdge(PkgEdge(
      sourceId: sourceId,
      targetId: targetId,
      type: EdgeType.navigatesTo,
      label: navigation.api,
    ));
  }

  Map<String, Object?> _actionProperties(ActionSummary action) => {
        if (action.calls.isNotEmpty) 'calls': action.calls,
        if (action.stateChanges.isNotEmpty) 'stateChanges': action.stateChanges,
        if (action.effects.isNotEmpty) 'effects': action.effects,
        'isAsync': action.isAsync,
      };
}
