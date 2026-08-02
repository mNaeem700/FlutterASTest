import 'package:flutterastest/orchestrator/pipeline_context.dart';
import 'package:flutterastest/orchestrator/pipeline_stage.dart';
import 'package:flutterastest/analysis/analysis_result.dart';
import 'package:flutterastest/orchestrator/contracts/pipeline_module.dart';
import 'prompt_context_generator.dart';
import 'models/prompt_context.dart';

class PromptModule implements PipelineModule {
  final PromptContextGenerator _generator;

  PromptModule({PromptContextGenerator? generator})
      : _generator = generator ?? PromptContextGenerator();

  @override
  // Use whatever stage enum you have next, or fallback to analysis if prompt isn't defined yet
  get stage => PipelineStage.analysis;

  @override
  Future<PipelineContext> execute(PipelineContext context) async {
    final analysisResult = context.get<AnalysisResult>();

    if (analysisResult == null) {
      throw Exception('AnalysisResult missing from PipelineContext!');
    }

    // Generate the contexts
    final promptContexts = _generator.generate(analysisResult);

    // Save to context for the next phase (LLM)
    context.put<List<PromptContext>>(promptContexts);

    // Inside PromptModule.execute():
    final contexts = _generator.generate(analysisResult);
    context.put<List<PromptContext>>(contexts); // 👇 Add this line!

    return context;
  }
}
