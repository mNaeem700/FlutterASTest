import 'dart:io';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import '../prompt_builder/models/prompt_context.dart';
import 'prompt_optimizer.dart';
import 'prompt_builder.dart';

class PromptOptimizerModule implements PipelineModule {
  @override
  PipelineStage get stage => PipelineStage.analysis;

  @override
  Future<void> execute(PipelineContext context) async {
    print('\nOptimizing Prompts & Generating Output Files...');
    print('-----------------------------------------------');

    final promptContexts = context.get<List<PromptContext>>();

    if (promptContexts == null || promptContexts.isEmpty) {
      throw Exception(
          'No PromptContexts found! Ensure PromptModule saves them to PipelineContext.');
    }

    final optimizer = PromptOptimizer();
    final builder = PromptBuilder();

    // Create output directory
    final outputDir = Directory('output/prompts');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    int savedCount = 0;

    for (final promptContext in promptContexts) {
      // 1. Optimize the context
      final optimized = optimizer.optimize(promptContext);

      // 2. Build the final LLM string with instructions
      final finalPromptText = builder.buildSystemPrompt(optimized);

      // 3. Save to .txt file
      final file = File('${outputDir.path}/${optimized.screenName}_prompt.txt');
      await file.writeAsString(finalPromptText);
      savedCount++;
    }

    print(
        'Successfully optimized and saved $savedCount prompt files to ${outputDir.path}/');
  }
}
