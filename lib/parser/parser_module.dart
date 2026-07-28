import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import 'dart_file_finder.dart';
import 'parser_engine.dart';
import 'models/parser_result.dart';
import 'import_extractor.dart';
import 'models/import_model.dart';
import 'declaration_extractor.dart';
import 'models/declaration_model.dart';
import 'diagnostic_extractor.dart';
import 'models/diagnostic_model.dart';
import 'models/parser_metrics.dart'; // Metrics import karein

class ParserModule implements PipelineModule {
  ParserModule({
    DartFileFinder? fileFinder,
    ParserEngine? engine,
  })  : _fileFinder = fileFinder ?? const DartFileFinder(),
        _engine = engine ?? const ParserEngine();

  final DartFileFinder _fileFinder;
  final ParserEngine _engine;

  @override
  String get name => 'Parser Module';

  @override
  PipelineStage get stage => PipelineStage.parser;

  @override
  Future<void> execute(PipelineContext context) async {
    final overallStopwatch = Stopwatch()..start();
    final stepStopwatch = Stopwatch()..start();

    final projectPath = context.projectPath;

    // 1. File Discovery
    final dartFiles = await _fileFinder.findFiles(projectPath);
    final discoveryTime = stepStopwatch.elapsedMilliseconds;
    stepStopwatch.reset();

    if (dartFiles.isEmpty) {
      print('No Dart files found. Skipping parsing.');
      return; // Basic exit if empty
    }

    // 2. AST Resolution
    final resolvedUnits = await _engine.parseProject(
      projectRoot: projectPath,
      filePaths: dartFiles,
    );
    final astTime = stepStopwatch.elapsedMilliseconds;
    stepStopwatch.reset();

    // Extractors setup
    final importExtractor = const ImportExtractor();
    final declarationExtractor = const DeclarationExtractor();
    final diagnosticExtractor = const DiagnosticExtractor();

    final allImports = <ImportModel>[];
    final allDeclarations = <DeclarationModel>[];
    final allDiagnostics = <DiagnosticModel>[];

    // 3. Extraction (Combined loop)
    for (final resolvedUnit in resolvedUnits) {
      allImports.addAll(importExtractor.extract(resolvedUnit.unit));

      allDeclarations.addAll(declarationExtractor.extract(
        unit: resolvedUnit.unit,
        filePath: resolvedUnit.path,
      ));

      allDiagnostics.addAll(diagnosticExtractor.extract(resolvedUnit));
    }
    final extractionTime = stepStopwatch.elapsedMilliseconds;

    overallStopwatch.stop();

    // 4. Create Metrics Object
    final metrics = ParserMetrics(
      totalFiles: dartFiles.length,
      parsedFiles: resolvedUnits.length,
      failedFiles: dartFiles.length - resolvedUnits.length,
      totalImports: allImports.length,
      totalDeclarations: allDeclarations.length,
      totalDiagnostics: allDiagnostics.length,
      executionTime: overallStopwatch.elapsed,
    );

    // Print Report
    print('\nParser Performance');
    print('------------------');
    print('File Discovery        : $discoveryTime ms');
    print('AST Resolution        : $astTime ms');
    print('Extraction Phase      : $extractionTime ms');
    print(
        'Total                 : ${overallStopwatch.elapsedMilliseconds} ms\n');

    final parserResult = ParserResult(
      resolvedUnits: resolvedUnits,
      imports: List.unmodifiable(allImports),
      declarations: List.unmodifiable(allDeclarations),
      diagnostics: List.unmodifiable(allDiagnostics),
      metrics: metrics,
    );

    context.put<ParserResult>(parserResult);
    print('ParserResult created successfully.');
  }
}
