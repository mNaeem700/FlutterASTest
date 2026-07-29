import 'package:meta/meta.dart';

@immutable
class StateMutation {
  const StateMutation({
    required this.variableName,
    required this.enclosingClass,
    required this.enclosingMethod,
    required this.mutationType,
    required this.sourceLine,
  });

  final String variableName;
  final String enclosingClass;
  final String enclosingMethod;
  final String
      mutationType; // assignment, compoundAssignment, incrementDecrement, collectionMutation, rxUpdate
  final int sourceLine;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateMutation &&
          runtimeType == other.runtimeType &&
          variableName == other.variableName &&
          enclosingClass == other.enclosingClass &&
          enclosingMethod == other.enclosingMethod &&
          sourceLine == other.sourceLine;

  @override
  int get hashCode =>
      variableName.hashCode ^
      enclosingClass.hashCode ^
      enclosingMethod.hashCode ^
      sourceLine.hashCode;

  Map<String, dynamic> toJson() {
    return {
      'variableName': variableName,
      'enclosingClass': enclosingClass,
      'enclosingMethod': enclosingMethod,
      'mutationType': mutationType,
      'sourceLine': sourceLine,
    };
  }
}
