enum NodeType {
  screen,
  widget,
  interaction,
  dependency,
  member,
  stateField,
  route,
  lifecycle,
}

class PkgNode {
  PkgNode({
    required this.id,
    required this.label,
    required this.type,
    Map<String, Object?> properties = const {},
  }) : properties = Map.unmodifiable(properties);

  /// Canonical id: `Package::File::Entity::SourceOffset` (Doc 9.19.1).
  final String id;
  final String label;
  final NodeType type;
  final Map<String, Object?> properties;

  T? property<T>(String key) {
    final value = properties[key];
    return value is T ? value : null;
  }

  List<String> stringList(String key) =>
      (properties[key] as List?)?.cast<String>() ?? const [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'label': label,
        if (properties.isNotEmpty) 'properties': properties,
      };

  @override
  String toString() => '$label (${type.name})';
}
