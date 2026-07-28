import 'package:meta/meta.dart';

@immutable
class ParserMetrics {
  const ParserMetrics({
    required this.totalFiles,
    required this.parsedFiles,
    required this.failedFiles,
    required this.totalImports,
    required this.totalDeclarations,
    required this.totalDiagnostics,
    required this.executionTime,
  });

  final int totalFiles;
  final int parsedFiles;
  final int failedFiles;
  final int totalImports;
  final int totalDeclarations;
  final int totalDiagnostics;
  final Duration executionTime;
}
