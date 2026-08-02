enum EdgeType {
  contains, // e.g., Screen -> Widget
  uses, // e.g., Screen -> Controller / Dependency
  navigates, // e.g., Callback -> Screen
  calls, // e.g., Widget -> Callback Method
  owns, // e.g., Controller -> Variable
}

class PkgEdge {
  final String sourceId;
  final String targetId;
  final EdgeType type;
  final String? description;

  PkgEdge({
    required this.sourceId,
    required this.targetId,
    required this.type,
    this.description,
  });

  @override
  String toString() => '$sourceId --[$type]--> $targetId';
}
