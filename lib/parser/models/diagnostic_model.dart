import 'package:meta/meta.dart';

@immutable
class DiagnosticModel {
  const DiagnosticModel({
    required this.code,
    required this.message,
    required this.severity,
    required this.filePath,
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
  });

  final String code;

  final String message;

  final String severity;

  final String filePath;

  final int offset;

  final int length;

  final int line;

  final int column;
}
