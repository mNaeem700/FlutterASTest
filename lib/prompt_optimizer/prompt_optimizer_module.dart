import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/analysis_result.dart';
import '../experiment/experiment_config.dart';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import '../prompt_builder/models/prompt_context.dart';
import 'models/test_prompt.dart';
import 'prompt_builder.dart';

/// Turns each screen's context into the final prompt and writes it to
/// `output/runs/<run>/prompts/` for inspection.
class PromptOptimizerModule implements PipelineModule {
  const PromptOptimizerModule({PromptBuilder builder = const PromptBuilder()})
      : _builder = builder;

  final PromptBuilder _builder;

  @override
  PipelineStage get stage => PipelineStage.promptBuilder;

  @override
  Future<void> execute(PipelineContext context) async {
    print('\nWriting prompt files...');
    print('-----------------------');

    final config = context.get<ExperimentConfig>() ?? const ExperimentConfig();
    final promptContexts = context.get<List<PromptContext>>();
    final analysis = context.get<AnalysisResult>();
    if (promptContexts == null || analysis == null) {
      throw Exception('PromptContexts or AnalysisResult missing from PipelineContext!');
    }

    // Results of an earlier run of the same mode must not leak into this one.
    final runDir = Directory(config.runDirectory);
    if (await runDir.exists()) {
      await runDir.delete(recursive: true);
    }
    final promptDir = Directory(p.join(runDir.path, 'prompts'));
    await promptDir.create(recursive: true);

    final screenFiles = {
      for (final screen in analysis.screenContexts) screen.name: screen.relativePath,
    };

    final prompts = <TestPrompt>[];
    var totalChars = 0;
    for (final promptContext in promptContexts) {
      final text = config.ablation == Ablation.noPromptBuilder
          ? _builder.buildMinimal(
              packageName: analysis.projectInfo.packageName,
              screenName: promptContext.screenName,
              contextTitle: config.contextTitle,
              context: promptContext.context,
            )
          : _builder.build(
              project: analysis.projectInfo,
              screenName: promptContext.screenName,
              importUri: promptContext.importUri,
              navigationImports: promptContext.navigationImports,
              contextTitle: config.contextTitle,
              context: promptContext.context,
            );
      totalChars += text.length;
      prompts.add(TestPrompt(
        screenName: promptContext.screenName,
        screenFile: screenFiles[promptContext.screenName] ?? '',
        text: text,
      ));
      await File(p.join(promptDir.path, '${promptContext.screenName}_prompt.txt'))
          .writeAsString(text);
    }

    context.put<List<TestPrompt>>(prompts);

    final count = prompts.length;
    print('Mode: ${config.mode.name}');
    print('Saved $count prompt files to ${promptDir.path}${p.separator} '
        '(template v${PromptBuilder.templateVersion})');
    print('Average prompt size: ${count == 0 ? 0 : (totalChars / count).round()} characters\n');
  }
}
