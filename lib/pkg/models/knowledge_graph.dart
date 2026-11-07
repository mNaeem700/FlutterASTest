import 'pkg_edge.dart';
import 'pkg_node.dart';

/// Program Knowledge Graph: typed nodes and typed, ordered directed edges.
class KnowledgeGraph {
  final Map<String, PkgNode> _nodes = {};
  final List<PkgEdge> _edges = [];
  final Set<String> _edgeKeys = {};
  final Map<String, List<PkgEdge>> _outgoing = {};

  List<PkgNode> get nodes => List.unmodifiable(_nodes.values);
  List<PkgEdge> get edges => List.unmodifiable(_edges);

  /// Adds [node]; the first node with a given id wins.
  PkgNode addNode(PkgNode node) => _nodes.putIfAbsent(node.id, () => node);

  void addEdge(PkgEdge edge) {
    if (!_nodes.containsKey(edge.sourceId) || !_nodes.containsKey(edge.targetId)) {
      throw StateError('Edge $edge references a missing node.');
    }
    if (_edgeKeys.add(edge.key)) {
      _edges.add(edge);
      _outgoing.putIfAbsent(edge.sourceId, () => []).add(edge);
    }
  }

  PkgNode? getNode(String id) => _nodes[id];

  /// Outgoing edges of [sourceId] of [type], in sibling order.
  List<PkgEdge> outgoing(String sourceId, EdgeType type) {
    final edges = (_outgoing[sourceId] ?? const <PkgEdge>[])
        .where((e) => e.type == type)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return edges;
  }

  /// All outgoing edges of [sourceId], in insertion order.
  List<PkgEdge> allOutgoing(String sourceId) => _outgoing[sourceId] ?? const [];

  List<PkgNode> targets(String sourceId, EdgeType type) => [
        for (final edge in outgoing(sourceId, type)) _nodes[edge.targetId]!,
      ];

  List<PkgNode> nodesOfType(NodeType type) =>
      _nodes.values.where((n) => n.type == type).toList();

  Map<String, dynamic> toJson() => {
        'nodes': _nodes.values.map((n) => n.toJson()).toList(),
        'edges': _edges.map((e) => e.toJson()).toList(),
      };
}
