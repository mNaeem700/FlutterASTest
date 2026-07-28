import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/file_system/physical_file_system.dart';

class ParserEngine {
  const ParserEngine();

  Future<List<ResolvedUnitResult>> parseProject({
    required String projectRoot,
    required List<String> filePaths,
  }) async {
    if (filePaths.isEmpty) return [];

    final collection = AnalysisContextCollection(
      includedPaths: [projectRoot],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );

    final results = <ResolvedUnitResult>[];

    for (final context in collection.contexts) {
      final session = context.currentSession;

      final contextFiles = filePaths
          .where((path) => context.contextRoot.isAnalyzed(path))
          .toList(); // List mein convert kiya

      // 🚀 ASYNC BATCHING: Ek ek karke wait karne ke bajaye sab files ko aik sath bhej diya!
      final futures = contextFiles.map((path) => session.getResolvedUnit(path));

      // Future.wait sab ko parallel process karega
      final resolvedList = await Future.wait(futures);

      for (final result in resolvedList) {
        if (result is ResolvedUnitResult) {
          results.add(result);
        }
      }
    }

    return results;
  }
}
