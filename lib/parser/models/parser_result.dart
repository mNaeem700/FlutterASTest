import 'package:analyzer/dart/analysis/results.dart';
import 'import_model.dart';
import 'declaration_model.dart';
import 'diagnostic_model.dart';
import 'parser_metrics.dart'; // Nayi import

class ParserResult {
  const ParserResult({
    required this.resolvedUnits,
    required this.imports,
    required this.declarations,
    required this.diagnostics,
    required this.metrics, // Naya variable
  });

  final List<ResolvedUnitResult> resolvedUnits;
  final List<ImportModel> imports;
  final List<DeclarationModel> declarations;
  final List<DiagnosticModel> diagnostics;
  final ParserMetrics metrics; // Metrics add kar diye

  int get totalFiles => resolvedUnits.length;
}
