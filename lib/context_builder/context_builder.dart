import 'dart:collection';

import '../pkg/models/knowledge_graph.dart';
import '../pkg/models/pkg_edge.dart';
import '../pkg/models/pkg_node.dart';

/// Context Builder settings (Doc 10.21); the defaults are the locked values.
class ContextConfiguration {
  const ContextConfiguration({
    this.maxTraversalDepth = 5,
    this.alpha = 0.35,
    this.beta = 0.25,
    this.gamma = 0.25,
    this.delta = 0.15,
    this.relevanceThreshold = 0,
    this.tokenBudget = 8000,
    this.enabled = true,
    this.excludedEdges = const {},
  });

  /// Semantic hops allowed from the screen. Containment edges are the
  /// screen's immediate UI hierarchy, which Doc 10.19.1 makes mandatory, so
  /// they do not consume depth.
  final int maxTraversalDepth;
  final double alpha, beta, gamma, delta;
  final double relevanceThreshold;
  final int tokenBudget;

  /// False removes selection altogether (ablation A2): everything reachable
  /// is kept, with no depth limit, scoring, pruning or compression.
  final bool enabled;

  /// Relationships ignored during traversal (ablation A1).
  final Set<EdgeType> excludedEdges;
}

/// What the Context Builder selected for one screen (Doc 10.16.1).
class ContextPackage {
  ContextPackage({
    required this.screenId,
    required this.selected,
    required this.scores,
    required this.collapsed,
    required this.visitedNodes,
    required this.exploredEdges,
    required this.prunedNodes,
    required this.overBudget,
  });

  final String screenId;
  final Set<String> selected;
  final Map<String, double> scores;

  /// Trivial layout wrappers left out of the rendered tree (Doc 10.15).
  final Set<String> collapsed;
  final int visitedNodes;
  final int exploredEdges;
  final int prunedNodes;

  /// Mandatory entities alone exceed the budget.
  final bool overBudget;

  double get compressionRatio =>
      selected.isEmpty ? 1 : (selected.length - collapsed.length) / selected.length;

  Map<String, dynamic> metrics() => {
        'traversalStrategy': 'BFS',
        'visitedNodes': visitedNodes,
        'exploredEdges': exploredEdges,
        'selectedNodes': selected.length,
        'collapsedNodes': collapsed.length,
        'prunedNodes': prunedNodes,
        'compressionRatio': double.parse(compressionRatio.toStringAsFixed(4)),
        'overBudget': overBudget,
      };
}

/// Selects the PKG entities for a screen: bounded BFS, relevance scoring
/// `0.35W + 0.25N + 0.25S + 0.15D`, threshold filter, trivial-chain
/// compression and deterministic pruning to the token budget.
class ContextBuilder {
  const ContextBuilder({this.config = const ContextConfiguration()});

  final ContextConfiguration config;

  /// Layout-only wrappers carry nothing a test can find or act on.
  static const _trivialWrappers = {
    'Padding',
    'Center',
    'Align',
    'SizedBox',
    'Container',
    'Expanded',
    'Flexible',
    'SafeArea',
    'Positioned',
    'ClipRRect',
    'Opacity',
    'SingleChildScrollView',
  };

  ContextPackage build(
    KnowledgeGraph graph,
    PkgNode screen, {
    required int Function(ContextPackage draft) estimateTokens,
  }) {
    final distance = <String, int>{screen.id: 0};
    final queue = Queue<(String, int)>()..add((screen.id, 0));
    var explored = 0;

    while (queue.isNotEmpty) {
      final (id, semantic) = queue.removeFirst();
      // A destination screen is linked, not expanded: its tree is not context
      // for this screen.
      if (id != screen.id && graph.getNode(id)!.type == NodeType.screen) continue;
      for (final edge in graph.allOutgoing(id)) {
        if (config.excludedEdges.contains(edge.type)) continue;
        explored++;
        final hops = semantic + (edge.type == EdgeType.contains ? 0 : 1);
        if (config.enabled && hops > config.maxTraversalDepth) continue;
        if (distance.containsKey(edge.targetId)) continue;
        distance[edge.targetId] = distance[id]! + 1;
        queue.add((edge.targetId, hops));
      }
    }

    final scores = {
      for (final entry in distance.entries)
        entry.key: score(graph, graph.getNode(entry.key)!, entry.value),
    };

    if (!config.enabled) {
      return ContextPackage(
        screenId: screen.id,
        selected: distance.keys.toSet(),
        scores: scores,
        collapsed: const {},
        visitedNodes: distance.length,
        exploredEdges: explored,
        prunedNodes: 0,
        overBudget: false,
      );
    }

    final mandatory = _mandatory(graph, screen, distance.keys.toSet());
    final selected = {
      for (final id in distance.keys)
        if (mandatory.contains(id) || scores[id]! >= config.relevanceThreshold) id,
    };

    ContextPackage draft(bool over, int pruned) => ContextPackage(
          screenId: screen.id,
          selected: selected,
          scores: scores,
          collapsed: _collapsible(graph, selected),
          visitedNodes: distance.length,
          exploredEdges: explored,
          prunedNodes: pruned,
          overBudget: over,
        );

    // Stage 1 of Doc 10.19.1 considers every non-mandatory entity, so it also
    // covers what depth reduction and optional-edge removal would drop.
    var pruned = 0;
    while (estimateTokens(draft(false, pruned)) > config.tokenBudget) {
      final removable = [
        for (final id in selected)
          if (!mandatory.contains(id) && !_hasSelectedChild(graph, id, selected)) id,
      ]..sort((a, b) {
          final byScore = scores[a]!.compareTo(scores[b]!);
          return byScore != 0 ? byScore : b.compareTo(a);
        });
      if (removable.isEmpty) return draft(true, pruned);
      selected.remove(removable.first);
      pruned++;
    }
    return draft(false, pruned);
  }

  /// Score = αW + βN + γS + δD with D = 1 / (1 + d); all parts are in [0,1].
  double score(KnowledgeGraph graph, PkgNode node, int distance) =>
      config.alpha * widgetImportance(graph, node) +
      config.beta * navigationRelevance(graph, node) +
      config.gamma * stateDependency(graph, node) +
      config.delta * (1 / (1 + distance));

  static double widgetImportance(KnowledgeGraph graph, PkgNode node) => switch (node.type) {
        NodeType.screen || NodeType.interaction || NodeType.validation => 1,
        NodeType.widget => graph.outgoing(node.id, EdgeType.triggers).isNotEmpty
            ? 1
            : (node.stringList('labels').isNotEmpty || node.property<String>('key') != null)
                ? 0.6
                : 0.2,
        _ => 0,
      };

  static double navigationRelevance(KnowledgeGraph graph, PkgNode node) {
    bool navigates(String id) => graph.outgoing(id, EdgeType.navigatesTo).isNotEmpty;
    return switch (node.type) {
      NodeType.route || NodeType.screen => 1,
      NodeType.interaction || NodeType.lifecycle => navigates(node.id) ? 1 : 0,
      NodeType.widget =>
        graph.targets(node.id, EdgeType.triggers).any((i) => navigates(i.id)) ? 0.75 : 0,
      _ => 0,
    };
  }

  static double stateDependency(KnowledgeGraph graph, PkgNode node) => switch (node.type) {
        NodeType.stateField || NodeType.member => 1,
        NodeType.dependency || NodeType.lifecycle => 0.75,
        NodeType.interaction => (node.stringList('stateChanges').isNotEmpty ||
                graph.outgoing(node.id, EdgeType.calls).isNotEmpty)
            ? 1
            : 0,
        _ => 0,
      };

  /// Screen, directly associated state nodes and immediate UI hierarchy
  /// (Doc 10.19.1): build() roots and their direct children.
  static Set<String> _mandatory(KnowledgeGraph graph, PkgNode screen, Set<String> reached) {
    final mandatory = <String>{screen.id};
    for (final field in graph.targets(screen.id, EdgeType.bindsState)) {
      mandatory.add(field.id);
    }
    for (final root in graph.targets(screen.id, EdgeType.contains)) {
      mandatory.add(root.id);
      mandatory.addAll(graph.targets(root.id, EdgeType.contains).map((n) => n.id));
    }
    return mandatory.intersection(reached);
  }

  /// A node stays while something beneath it is selected, so pruning never
  /// disconnects the tree.
  static bool _hasSelectedChild(KnowledgeGraph graph, String id, Set<String> selected) {
    for (final edge in graph.allOutgoing(id)) {
      if (const {EdgeType.contains, EdgeType.triggers, EdgeType.declares, EdgeType.validates}.contains(edge.type) &&
          selected.contains(edge.targetId)) {
        return true;
      }
    }
    return false;
  }

  static Set<String> _collapsible(KnowledgeGraph graph, Set<String> selected) {
    final collapsed = <String>{};
    for (final id in selected) {
      final node = graph.getNode(id)!;
      if (node.type != NodeType.widget || !_trivialWrappers.contains(node.label)) continue;
      if (node.stringList('labels').isNotEmpty || node.property<String>('key') != null) continue;
      if (graph.outgoing(id, EdgeType.triggers).isNotEmpty) continue;
      if (graph.targets(id, EdgeType.contains).where((c) => selected.contains(c.id)).length == 1) {
        collapsed.add(id);
      }
    }
    return collapsed;
  }
}
