import 'package:meta/meta.dart';

import 'declaration_type.dart';

@immutable
class DeclarationModel {
  const DeclarationModel({
    required this.name,
    required this.type,
    required this.filePath,
    required this.offset,
    required this.endOffset,
    required this.annotations,
    required this.modifiers,
  });

  final String name;

  final DeclarationType type;

  final String filePath;

  final int offset;

  final int endOffset;

  final List<String> annotations;

  final List<String> modifiers;
}
