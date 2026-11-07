enum EdgeType {
  /// Screen → root widget, widget → child widget (ordered).
  contains,

  /// Widget → interaction it handles.
  triggers,

  /// Interaction or lifecycle hook → dependency member it calls.
  calls,

  /// Screen, interaction or lifecycle hook → screen or route.
  navigatesTo,

  /// Screen → dependency it obtains or uses.
  dependsOn,

  /// Dependency → member it declares (shared by every screen using it).
  declares,

  /// Screen → dependency member that this screen accesses (ordered).
  uses,

  /// Screen → its State class field.
  bindsState,

  /// Screen → lifecycle hook (initState, dispose, ...).
  hasLifecycle,
}

class PkgEdge {
  const PkgEdge({
    required this.sourceId,
    required this.targetId,
    required this.type,
    this.order = 0,
    this.label,
  });

  final String sourceId;
  final String targetId;
  final EdgeType type;

  /// Position among siblings, so child widgets keep their source order.
  final int order;

  /// Extra edge information, e.g. the navigation API for navigatesTo.
  final String? label;

  String get key => '$sourceId|${type.name}|$targetId|${label ?? ''}';

  Map<String, dynamic> toJson() => {
        'source': sourceId,
        'target': targetId,
        'type': type.name,
        if (order != 0) 'order': order,
        if (label != null) 'label': label,
      };

  @override
  String toString() => '$sourceId --[${type.name}]--> $targetId';
}
