import '../models/architecture_health_model.dart';
import '../models/dependency_edge.dart';
import '../models/navigation_edge.dart';

class ArchitectureHealthAnalyzer {
  const ArchitectureHealthAnalyzer({this.topReferencedLimit = 5});

  final int topReferencedLimit;

  ArchitectureHealthModel analyse({
    required List<dynamic> dependencies,
    required List<dynamic> navigation,
  }) {
    final edges = dependencies.whereType<DependencyEdge>().toList();
    final navEdges = navigation.whereType<NavigationEdge>().toList();

    final distribution = <String, int>{
      for (final type in DependencyType.values) type.name: 0,
    };
    final inDegree = <String, int>{};
    final graph = <String, Set<String>>{};

    for (final edge in edges) {
      distribution[edge.type.name] = distribution[edge.type.name]! + 1;
      inDegree[edge.to] = (inDegree[edge.to] ?? 0) + 1;
      graph.putIfAbsent(edge.from, () => <String>{}).add(edge.to);
      graph.putIfAbsent(edge.to, () => <String>{});
    }

    final ranked = inDegree.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    return ArchitectureHealthModel(
      dependencyDistribution: distribution,
      referencedClasses: {
        for (final e in ranked.take(topReferencedLimit)) e.key: e.value,
      },
      circularDependencies: _findCycles(graph),
      navigationEdges: navEdges.length,
      navigationSources: navEdges.map((e) => e.fromScreen).toSet().length,
      navigationTargets: navEdges.map((e) => e.toScreen).toSet().length,
    );
  }

  /// Tarjan's strongly connected components; nodes are visited in sorted
  /// order so the output is identical across runs.
  List<String> _findCycles(Map<String, Set<String>> graph) {
    var index = 0;
    final indices = <String, int>{};
    final lowLinks = <String, int>{};
    final onStack = <String>{};
    final stack = <String>[];
    final cycles = <String>[];

    void strongConnect(String node) {
      indices[node] = index;
      lowLinks[node] = index;
      index++;
      stack.add(node);
      onStack.add(node);

      final successors = graph[node]!.toList()..sort();
      for (final next in successors) {
        if (!indices.containsKey(next)) {
          strongConnect(next);
          lowLinks[node] = _min(lowLinks[node]!, lowLinks[next]!);
        } else if (onStack.contains(next)) {
          lowLinks[node] = _min(lowLinks[node]!, indices[next]!);
        }
      }

      if (lowLinks[node] == indices[node]) {
        final component = <String>[];
        String member;
        do {
          member = stack.removeLast();
          onStack.remove(member);
          component.add(member);
        } while (member != node);

        final isSelfLoop = component.length == 1 && graph[node]!.contains(node);
        if (component.length > 1 || isSelfLoop) {
          component.sort();
          cycles.add([...component, component.first].join(' → '));
        }
      }
    }

    for (final node in graph.keys.toList()..sort()) {
      if (!indices.containsKey(node)) strongConnect(node);
    }

    cycles.sort();
    return cycles;
  }

  int _min(int a, int b) => a < b ? a : b;
}
