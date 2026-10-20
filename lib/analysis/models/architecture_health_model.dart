class ArchitectureHealthModel {
  /// Dependency edge count per [DependencyType] name.
  final Map<String, int> dependencyDistribution;

  /// Most depended-upon classes (in-degree in the dependency graph).
  final Map<String, int> referencedClasses;

  /// Each entry is one strongly connected component of size > 1, or a
  /// self-dependency, rendered as "A → B → A".
  final List<String> circularDependencies;

  final int navigationEdges;
  final int navigationSources;
  final int navigationTargets;

  const ArchitectureHealthModel({
    required this.dependencyDistribution,
    required this.referencedClasses,
    required this.circularDependencies,
    required this.navigationEdges,
    required this.navigationSources,
    required this.navigationTargets,
  });

  Map<String, dynamic> toJson() => {
        'dependencyDistribution': dependencyDistribution,
        'referencedClasses': referencedClasses,
        'circularDependencies': circularDependencies,
        'navigationEdges': navigationEdges,
        'navigationSources': navigationSources,
        'navigationTargets': navigationTargets,
      };
}
