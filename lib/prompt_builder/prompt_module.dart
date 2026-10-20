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
  get stage => PipelineStage.contextBuilder;

  @override
  Future<PipelineContext> execute(PipelineContext context) async {
    final analysisResult = context.get<AnalysisResult>();

    if (analysisResult == null) {
      throw Exception('AnalysisResult missing from PipelineContext!');
    }

    final promptContexts = _generator.generate(analysisResult);
    context.put<List<PromptContext>>(promptContexts);

    return context;
  }
}
