import 'package:meta/meta.dart';
import 'state_variable.dart';
import 'state_mutation.dart'; // 👇 ADD IMPORT

@immutable
class StateModel {
  const StateModel({
    required this.className,
    required this.framework,
    required this.variables,
    required this.mutatorMethods,
    required this.triggers,
    required this.mutations, // 👇 ADDED
  });

  final String className;
  final String framework;
  final List<StateVariable> variables;
  final List<String> mutatorMethods;
  final List<String> triggers;
  final List<StateMutation> mutations; // 👇 ADDED

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StateModel &&
          runtimeType == other.runtimeType &&
          className == other.className &&
          framework == other.framework;

  @override
  int get hashCode => className.hashCode ^ framework.hashCode;

  @override
  String toString() {
    return 'StateModel(className: $className, variables: ${variables.length}, mutations: ${mutations.length})';
  }

  Map<String, dynamic> toJson() {
    return {
      'className': className,
      'framework': framework,
      'variables': variables.map((v) => v.name).toList(),
      'mutatorMethods': mutatorMethods,
      'triggers': triggers,
      'mutations': mutations.map((m) => m.toJson()).toList(),
    };
  }
}
