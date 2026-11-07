import 'package:analyzer/dart/analysis/results.dart';

import 'models/diagnostic_model.dart';

class DiagnosticExtractor {
  const DiagnosticExtractor();

  List<DiagnosticModel> extract(
    ResolvedUnitResult result,
  ) {
    final diagnostics = <DiagnosticModel>[];

    final lineInfo = result.lineInfo;

    for (final error in result.diagnostics) {
      final location = lineInfo.getLocation(
        error.offset,
      );

      diagnostics.add(
        DiagnosticModel(
          code: error.diagnosticCode.name,
          message: error.message,
          severity: error.diagnosticCode.severity.name,
          filePath: result.path,
          offset: error.offset,
          length: error.length,
          line: location.lineNumber,
          column: location.columnNumber,
        ),
      );
    }

    return List.unmodifiable(diagnostics);
  }
}
