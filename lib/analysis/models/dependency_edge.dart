import 'package:meta/meta.dart';

@immutable
class DependencyEdge {
  const DependencyEdge({
    required this.from,
    required this.to,
    required this.type,
    this.isExternal = false,
    this.packageName,
  });

  final String from;
  final String to;
  final DependencyType type;

  // 👇 ADDED: Metadata for future visualization and external package tracking
  final bool isExternal;
  final String? packageName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DependencyEdge &&
          runtimeType == other.runtimeType &&
          from == other.from &&
          to == other.to &&
          type == other.type &&
          isExternal == other.isExternal &&
          packageName == other.packageName;

  @override
  int get hashCode =>
      from.hashCode ^
      to.hashCode ^
      type.hashCode ^
      isExternal.hashCode ^
      (packageName?.hashCode ?? 0);

  @override
  String toString() {
    if (isExternal && packageName != null) {
      return 'DependencyEdge(from: $from, to: $to, type: ${type.name}, pkg: $packageName)';
    }
    return 'DependencyEdge(from: $from, to: $to, type: ${type.name})';
  }

  Map<String, dynamic> toJson() {
    return {
      'from': from,
      'to': to,
      'type': type.name,
      'isExternal': isExternal,
      'packageName': packageName,
    };
  }
}

enum DependencyType {
  constructor,
  field,
  objectCreation,
  modelComposition, // To separate DTO creation from general injection
  provider,
  riverpod,
  getx,
  bloc,
  cubit,
}
