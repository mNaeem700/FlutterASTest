import 'dart:io';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import '../prompt_builder/models/prompt_context.dart';
import 'prompt_optimizer.dart';
import 'prompt_builder.dart';

class PromptOptimizerModule implements PipelineModule {
  @override
  PipelineStage get stage => PipelineStage.promptBuilder;

  @override
  Future<void> execute(PipelineContext context) async {
    print('\nOptimizing Prompts & Generating Output Files...');
    print('-----------------------------------------------');

    final promptContexts = context.get<List<PromptContext>>();

    if (promptContexts == null || promptContexts.isEmpty) {
      throw Exception(
        'No PromptContexts found! Ensure PromptModule saves them to PipelineContext.',
      );
    }

    final optimizer = PromptOptimizer();
    final builder = PromptBuilder();

    // Create output directory
    final outputDir = Directory('output/prompts');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    int savedCount = 0;
    int totalPromptChars = 0;

    for (final promptContext in promptContexts) {
      final optimized = optimizer.optimize(promptContext);
      final finalPromptText = builder.buildSystemPrompt(optimized);
      totalPromptChars += finalPromptText.length;

      final file = File('${outputDir.path}/${optimized.screenName}_prompt.txt');
      await file.writeAsString(finalPromptText);
      savedCount++;
    }

    final averagePromptChars =
        savedCount > 0 ? (totalPromptChars / savedCount).round() : 0;

    print(
      'Successfully optimized and saved $savedCount prompt files to ${outputDir.path}/',
    );
    print('Average prompt size: $averagePromptChars characters\n');
  }
}
