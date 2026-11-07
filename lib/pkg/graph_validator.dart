import 'package:flutterastest/pkg/models/knowledge_graph.dart';
import 'package:flutterastest/pkg/models/pkg_edge.dart';

/// Checks the structural rules of Doc 9.19. Navigation cycles are valid and
/// are preserved; self-referential hierarchy edges and widgets with two
/// parents are not.
class GraphValidator {
  const GraphValidator();

  List<String> validate(KnowledgeGraph graph) {
    final problems = <String>[];
    final parents = <String, String>{};
    for (final edge in graph.edges) {
      if (edge.type != EdgeType.contains) continue;
      if (edge.sourceId == edge.targetId) {
        problems.add('Self-referential hierarchy edge: ${edge.sourceId}');
      }
      final parent = parents[edge.targetId];
      if (parent != null && parent != edge.sourceId) {
        problems.add('Duplicate parent for ${edge.targetId}: $parent, ${edge.sourceId}');
      }
      parents[edge.targetId] = edge.sourceId;
    }
    return problems;
  }
}
