import 'dart:io';

import '../analysis/analysis_result.dart';
import '../analysis/models/screen_context_model.dart';
import '../experiment/experiment_config.dart';
import '../experiment/models/screen_outcome.dart';
import '../experiment/run_artifacts.dart';
import '../llm/response_validator.dart';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import '../reflection/failure_analyzer.dart';
import 'flutter_test_runner.dart';
import 'lcov.dart';
import 'structural_coverage.dart';
import 'models/test_run.dart';

/// Runs an attempt's test file in the target project and records the result.
class AttemptExecutor {
  AttemptExecutor({
    required this.runner,
    required this.projectPath,
    required this.config,
    this.screens = const {},
  }) : _artifacts = RunArtifacts(config);

  /// Analysed screens by name, for structural coverage.
  final Map<String, ScreenContextModel> screens;

  final FlutterTestRunner runner;
  final String projectPath;
  final ExperimentConfig config;
  final RunArtifacts _artifacts;

  Future<TestRun> execute(ScreenOutcome outcome, Attempt attempt) async {
    final problems = const ResponseValidator().validate(attempt.code);
    if (problems.isNotEmpty) {
      final rejected = _withStructure(
        TestRun(
          compiled: false,
          cases: const [],
          durationMs: 0,
          loadErrors: problems,
          rejectedBeforeExecution: true,
        ),
        outcome,
        LcovReport(const {}),
      );
      attempt.run = rejected;
      return rejected;
    }

    Future<TestRun> runOnce(String lcovPath) async {
      try {
        return await runner.run(
          projectPath: projectPath,
          screenName: outcome.screenName,
          screenFile: outcome.screenFile,
          code: attempt.code,
          lcovPath: lcovPath,
          timeout: config.testTimeout,
        );
      } on Exception catch (e) {
        // One screen's failure must not end a long experiment.
        return TestRun(
            compiled: false, cases: const [], durationMs: 0, loadErrors: ['Could not run: $e']);
      }
    }

    final lcovPath = _artifacts.lcovFile(outcome.screenName, attempt.iteration);
    var run = await runOnce(lcovPath);

    // Doc 14 flaky policy: rerun a compiled file with failures. A test whose
    // outcome changes is flaky; it stays failed so results are not inflated.
    if (run.compiled && !run.timedOut && run.failed > 0 && config.flakyRetries > 0) {
      final status = {for (final c in run.cases) c.name: c.status};
      final flaky = <String>{};
      var duration = run.durationMs;
      for (var retry = 1; retry <= config.flakyRetries; retry++) {
        final again = await runOnce('$lcovPath.retry$retry');
        duration += again.durationMs;
        for (final c in again.cases) {
          if (status[c.name] != null && status[c.name] != c.status) flaky.add(c.name);
        }
      }
      run = run.copyWith(flakyTests: flaky.toList()..sort(), durationMs: duration);
    }

    final lcov = File(lcovPath);
    final report = lcov.existsSync()
        ? LcovReport.parse(lcov.readAsStringSync(), projectPath: projectPath)
        : LcovReport(const {});
    run = _withStructure(run, outcome, report);
    attempt.run = run;
    return run;
  }

  /// A run without coverage still reports what it failed to cover, so a test
  /// that does not compile counts as 0% rather than as missing data.
  TestRun _withStructure(TestRun run, ScreenOutcome outcome, LcovReport report) {
    final screen = screens[outcome.screenName];
    return run.copyWith(
      branchCoverage: report.branchesOf(outcome.screenFile),
      functionCoverage: report.functionsOf(outcome.screenFile),
      structural:
          screen == null ? null : const StructuralCoverageAnalyzer().analyse(screen, report),
    );
  }

  static String describe(TestRun run) {
    if (run.timedOut) return 'timed out';
    if (run.rejectedBeforeExecution) return 'rejected: ${run.loadErrors.first}';
    if (!run.compiled) return 'does not compile: ${run.reason ?? 'unknown error'}';
    final coverage = run.screenCoverage == null
        ? ''
        : ', line coverage ${(run.screenCoverage!.ratio * 100).toStringAsFixed(1)}%';
    final cause = run.failed > 0 && run.reason != null ? ' - ${run.reason}' : '';
    return '${run.passed} passed, ${run.failed} failed$coverage$cause';
  }
}

class ExecutorModule implements PipelineModule {
  ExecutorModule({FlutterTestRunner? runner}) : _runner = runner ?? FlutterTestRunner();

  final FlutterTestRunner _runner;

  @override
  PipelineStage get stage => PipelineStage.execution;

  @override
  Future<void> execute(PipelineContext context) async {
    print('\nExecuting generated tests in the target project...');
    print('--------------------------------------------------');

    final config = context.get<ExperimentConfig>() ?? const ExperimentConfig();
    final outcomes = context.get<List<ScreenOutcome>>();
    if (outcomes == null) {
      throw Exception('ScreenOutcomes missing from PipelineContext! Run the LLM module first.');
    }

    await FlutterTestRunner.cleanUp(context.projectPath);
    final executor = AttemptExecutor(
      runner: _runner,
      projectPath: context.projectPath,
      config: config,
      screens: {
        for (final screen in context.get<AnalysisResult>()?.screenContexts ?? const [])
          screen.name: screen,
      },
    );
    context.put<AttemptExecutor>(executor);

    for (var i = 0; i < outcomes.length; i++) {
      final outcome = outcomes[i];
      final attempt = outcome.last;
      if (attempt == null || attempt.run != null) continue;
      final run = await executor.execute(outcome, attempt);
      attempt.analysis = const FailureAnalyzer().analyse(run);
      print('[${i + 1}/${outcomes.length}] ${outcome.screenName.padRight(32)} '
          '${AttemptExecutor.describe(run)} '
          '(${(run.durationMs / 1000).toStringAsFixed(1)} s)');
    }
  }
}

/// Checks, before any LLM call, that the target project can run a widget
/// test at all, so a broken environment is never recorded as failing tests.
class PreflightModule implements PipelineModule {
  PreflightModule({FlutterTestRunner? runner}) : _runner = runner ?? FlutterTestRunner();

  final FlutterTestRunner _runner;

  @override
  PipelineStage get stage => PipelineStage.configuration;

  @override
  Future<void> execute(PipelineContext context) async {
    final config = context.get<ExperimentConfig>() ?? const ExperimentConfig();
    print('\nPreflight: running a trivial widget test in the target project...');
    final problem = await _runner.preflight(context.projectPath, timeout: config.testTimeout);
    if (problem != null) {
      throw Exception(
        'The target project cannot run widget tests, so the experiment was not started.\n'
        '$problem\n'
        'Fix the environment first: run `flutter pub get` in the project and make sure '
        '`flutter test` passes there. A "language version ... is too high" error means the '
        'Flutter SDK is only partly upgraded; run `flutter upgrade --force`.',
      );
    }
    print('Preflight passed.');
  }
}
