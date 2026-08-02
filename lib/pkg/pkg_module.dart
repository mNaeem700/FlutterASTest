import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import '../analysis/analysis_result.dart'; // 👇 ADD THIS IMPORT
import 'pkg_builder.dart';
import 'models/knowledge_graph.dart';

class PkgModule implements PipelineModule {
  @override
  PipelineStage get stage => PipelineStage.analysis;

  @override
  Future<void> execute(PipelineContext context) async {
    print('\nBuilding Program Knowledge Graph (PKG)...');
    print('-----------------------------------------');

    // 👇 1. Fetch AnalysisResult using your generic get<T>() method
    final analysisResult = context.get<AnalysisResult>();

    if (analysisResult == null) {
      throw Exception('AnalysisResult is missing from PipelineContext!');
    }

    final builder = PkgBuilder();

    // 👇 2. Build the Graph
    final KnowledgeGraph graph = builder.build(analysisResult);

    // 👇 3. Save the PKG back to the context using put<T>()
    context.put<KnowledgeGraph>(graph);

    print(
        'PKG built successfully with ${graph.nodes.length} nodes and ${graph.edges.length} edges.');
  }
}
