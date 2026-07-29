import 'package:meta/meta.dart';

@immutable
class StateVariable {
  const StateVariable({
    required this.name,
    required this.type,
    required this.isFinal,
    required this.isLate,
    required this.isNullable,
    required this.isStatic, // 👇 ADDED
    required this.category,
  });

  final String name;
  final String type;
  final bool isFinal;
  final bool isLate;
  final bool isNullable;
  final bool isStatic;
  final String category;
}
