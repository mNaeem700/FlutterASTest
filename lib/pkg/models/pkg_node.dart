enum NodeType {
  screen,
  widget,
  controller,
  variable,
  callback,
  repository,
  service,
  unknown
}

class PkgNode {
  final String id;
  final String label;
  final NodeType type;

  PkgNode({
    required this.id,
    required this.label,
    required this.type,
  });

  @override
  String toString() => '$label (${type.name})';
}
