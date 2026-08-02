class ArchitectureHealthModel {
  final Map<String, int> dependencyDistribution;
  final Map<String, int> widgetComplexityMap;
  final Map<String, int> referencedClasses;
  final List<String> circularDependencies;
  final List<Map<String, dynamic>> godClasses;
  final String navigationCoupling;
  final String dependencyCoupling;
  final String overallHealth;

  const ArchitectureHealthModel({
    required this.dependencyDistribution,
    required this.widgetComplexityMap,
    required this.referencedClasses,
    required this.circularDependencies,
    required this.godClasses,
    required this.navigationCoupling,
    required this.dependencyCoupling,
    required this.overallHealth,
  });

  Map<String, dynamic> toJson() => {
        'dependencyDistribution': dependencyDistribution,
        'widgetComplexityMap': widgetComplexityMap,
        'referencedClasses': referencedClasses,
        'circularDependencies': circularDependencies,
        'godClasses': godClasses,
        'navigationCoupling': navigationCoupling,
        'dependencyCoupling': dependencyCoupling,
        'overallHealth': overallHealth,
      };
}
