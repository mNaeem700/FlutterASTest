import 'dart:io';

import '../execution/executor_module.dart';
import '../execution/models/test_run.dart';
import '../experiment/experiment_config.dart';
import '../experiment/models/screen_outcome.dart';
import '../experiment/run_artifacts.dart';
import '../llm/llm_service.dart';
import '../llm/response_parser.dart';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import 'failure_analyzer.dart';
import 'repair_prompt_builder.dart';

/// Reflection loop (Doc 15): diagnoses each screen's run, sends the diagnosis
/// and coverage gaps back to the LLM and executes the improved file. Every
/// iteration starts from the best attempt so far. Doc 15.20.2's stopping
/// criteria apply: goal reached, maximum iterations, no change or repeated
/// failure (converged), and improvement below the threshold.
class ReflectionModule implements PipelineModule {
  ReflectionModule({
    required this.llmService,
    this.requestInterval = const Duration(seconds: 10),
    RepairPromptBuilder promptBuilder = const RepairPromptBuilder(),
    FailureAnalyzer analyzer = const FailureAnalyzer(),
  })  : _promptBuilder = promptBuilder,
        _analyzer = analyzer;

  final LlmService llmService;
  final Duration requestInterval;
  final RepairPromptBuilder _promptBuilder;
  final FailureAnalyzer _analyzer;

  @override
  PipelineStage get stage => PipelineStage.reflection;

  /// True when [run] leaves nothing for reflection to do.
  static bool goalReached(TestRun run, ExperimentConfig config) {
    if (!run.allPassed) return false;
    if (!config.coverageGuided) return true;
    final branchesMet = run.branchCoverage.found == 0 ||
        run.branchCoverage.value >= config.targetBranchCoverage;
    return (run.screenCoverage?.ratio ?? 0) >= config.targetLineCoverage && branchesMet;
  }

  @override
  Future<void> execute(PipelineContext context) async {
    final config = context.get<ExperimentConfig>() ?? const ExperimentConfig();
    final outcomes = context.get<List<ScreenOutcome>>();
    final executor = context.get<AttemptExecutor>();
    if (outcomes == null || executor == null) {
      throw Exception('ScreenOutcomes or AttemptExecutor missing from PipelineContext!');
    }

    print('\nReflection: improving tests (max ${config.maxIterations} iterations)...');
    print('---------------------------------------------------------------------');

    final artifacts = RunArtifacts(config);
    final parser = ResponseParser();
    var waitBeforeCall = false;

    for (final outcome in outcomes) {
      final start = outcome.best;
      if (start == null) continue;
      start.analysis = _analyzer.analyse(start.run!);
      if (goalReached(start.run!, config)) {
        outcome.stoppingReason = 'goal reached';
        continue;
      }
      if (start.code.trim().isEmpty) {
        outcome.stoppingReason = 'no code generated';
        continue;
      }
      print(outcome.screenName);
      outcome.stoppingReason = 'maximum iterations reached';

      final signatures = <String>{start.analysis!.signature};

      for (var iteration = 1; iteration <= config.maxIterations; iteration++) {
        final base = outcome.best!;
        final baseRank = ScreenOutcome.rank(base.run!);

        if (waitBeforeCall && requestInterval > Duration.zero) {
          await Future<void>.delayed(requestInterval);
        }

        final prompt = _promptBuilder.build(
          originalPrompt: outcome.prompt,
          previousCode: base.code,
          run: base.run!,
          iteration: iteration,
          analysis: base.analysis,
          coverageGuided: config.coverageGuided,
        );
        final response = await llmService.generate(prompt);
        waitBeforeCall = !response.fromCache;
        if (!response.succeeded) {
          print('  iteration $iteration: LLM call failed (${response.error}), stopping');
          outcome.stoppingReason = 'LLM call failed';
          break;
        }

        final code = parser.extractDartCode(response.text);
        final attempt = Attempt(iteration: iteration, generation: response, code: code);
        outcome.attempts.add(attempt);
        await artifacts.saveAttempt(outcome, attempt, prompt);

        if (code.trim() == base.code.trim()) {
          attempt.run = base.run!.copyWith(durationMs: 0);
          attempt.analysis = base.analysis;
          outcome.stoppingReason = 'no further change (converged)';
          print('  iteration $iteration: unchanged code returned, stopping');
          break;
        }

        final repaired = await executor.execute(outcome, attempt);
        attempt.analysis = _analyzer.analyse(repaired);
        print('  iteration $iteration: ${AttemptExecutor.describe(repaired)}');

        if (goalReached(repaired, config)) {
          outcome.stoppingReason = 'goal reached';
          break;
        }
        if (attempt.analysis!.hasFailures && !signatures.add(attempt.analysis!.signature)) {
          outcome.stoppingReason = 'repeated failure';
          break;
        }
        // Passing files are improved only for coverage, so they stop when the
        // gain is too small to be worth another LLM call.
        final gain = ScreenOutcome.rank(repaired) - baseRank;
        if (repaired.allPassed && base.run!.allPassed && gain < config.minimumImprovement * 0.5) {
          outcome.stoppingReason = 'improvement below threshold';
          break;
        }
      }

      final best = outcome.best;
      if (best != null) await File(artifacts.testFile(outcome.screenName)).writeAsString(best.code);
      print('  stopped: ${outcome.stoppingReason}');
    }
  }
}
