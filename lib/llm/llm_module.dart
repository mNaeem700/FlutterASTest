import 'dart:io';

import '../experiment/experiment_config.dart';
import '../experiment/models/screen_outcome.dart';
import '../experiment/run_artifacts.dart';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import '../prompt_optimizer/models/test_prompt.dart';
import 'gemini_llm_service.dart';
import 'llm_service.dart';
import 'response_parser.dart';

/// Generates the initial test file (iteration 0) of every screen.
class LlmModule implements PipelineModule {
  static const apiKeyVariable = 'GEMINI_API_KEY';

  LlmModule({
    LlmService? llmService,
    this.requestInterval = const Duration(seconds: 10),
  }) : llmService = llmService ?? GeminiLlmService(apiKey: readApiKeyFromEnvironment());

  final LlmService llmService;

  /// Pause between calls so free-tier rate limits are not hit.
  final Duration requestInterval;

  static String readApiKeyFromEnvironment() {
    final key = Platform.environment[apiKeyVariable];
    if (key == null || key.trim().isEmpty) {
      throw StateError(
        '$apiKeyVariable is not set. Set it in your shell before running '
        'FlutterASTest; the key must never be written into source code.',
      );
    }
    return key.trim();
  }

  @override
  PipelineStage get stage => PipelineStage.llm;

  @override
  Future<void> execute(PipelineContext context) async {
    print('\nGenerating widget tests via LLM (${llmService.model})...');
    print('------------------------------------------------------');

    final config = context.get<ExperimentConfig>() ?? const ExperimentConfig();
    final prompts = context.get<List<TestPrompt>>();
    if (prompts == null) {
      throw Exception('TestPrompts missing from PipelineContext!');
    }

    final artifacts = RunArtifacts(config);
    final parser = ResponseParser();
    final outcomes = <ScreenOutcome>[];

    for (var i = 0; i < prompts.length; i++) {
      final prompt = prompts[i];
      stdout.write('[${i + 1}/${prompts.length}] ${prompt.screenName} ... ');

      final response = await llmService.generate(prompt.text);
      final attempt = Attempt(
        iteration: 0,
        generation: response,
        code: response.succeeded ? parser.extractDartCode(response.text) : '',
      );
      final outcome = ScreenOutcome(
        screenName: prompt.screenName,
        screenFile: prompt.screenFile,
        prompt: prompt.text,
      )..attempts.add(attempt);
      outcomes.add(outcome);
      await artifacts.saveAttempt(outcome, attempt, prompt.text);

      print(response.succeeded
          ? '${response.promptTokens ?? '?'} prompt / ${response.outputTokens ?? '?'} output tokens, '
              '${(response.latencyMs / 1000).toStringAsFixed(1)} s'
          : 'FAILED: ${response.error}');

      if (i < prompts.length - 1 && requestInterval > Duration.zero) {
        await Future<void>.delayed(requestInterval);
      }
    }

    context.put<List<ScreenOutcome>>(outcomes);
    final generated = outcomes.where((o) => o.last!.generation.succeeded).length;
    print('\nGenerated $generated of ${outcomes.length} test files into ${artifacts.root}');
  }
}
