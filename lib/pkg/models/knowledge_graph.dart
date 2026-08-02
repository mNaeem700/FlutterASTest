import 'pkg_edge.dart';
import 'pkg_node.dart';

class KnowledgeGraph {
  final Map<String, PkgNode> _nodes = {};
  final List<PkgEdge> _edges = [];

  // Getters
  List<PkgNode> get nodes => _nodes.values.toList();
  List<PkgEdge> get edges => _edges;

  void addNode(PkgNode node) {
    _nodes[node.id] = node;
  }

  void addEdge(PkgEdge edge) {
    if (!_edges.any((e) =>
        e.sourceId == edge.sourceId &&
        e.targetId == edge.targetId &&
        e.type == edge.type)) {
      _edges.add(edge);
    }
  }

  PkgNode? getNode(String id) => _nodes[id];

  /// Core research feature: Query the graph!
  /// Example: Find everything a specific screen "uses" (Dependencies)
  List<PkgNode> getRelatedNodes(String sourceId, EdgeType edgeType) {
    final relatedEdges =
        _edges.where((e) => e.sourceId == sourceId && e.type == edgeType);
    return relatedEdges
        .map((e) => _nodes[e.targetId])
        .whereType<PkgNode>()
        .toList();
  }
}
