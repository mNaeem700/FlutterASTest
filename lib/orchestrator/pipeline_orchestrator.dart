import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'package:flutterastest/evaluation/evaluation_module.dart';
import 'package:flutterastest/execution/executor_module.dart';
import 'package:flutterastest/execution/flutter_command.dart';
import 'package:flutterastest/execution/flutter_test_runner.dart';
import 'package:flutterastest/analysis/analysis_result.dart';
import 'package:flutterastest/experiment/cpu_usage.dart';
import 'package:flutterastest/experiment/environment_info.dart';
import 'package:flutterastest/experiment/experiment_config.dart';
import 'package:flutterastest/pkg/models/knowledge_graph.dart';
import 'package:path/path.dart' as p;
import 'package:flutterastest/llm/caching_llm_service.dart';
import 'package:flutterastest/llm/circuit_breaker_llm_service.dart';
import 'package:flutterastest/llm/llm_factory.dart';
import 'package:flutterastest/llm/llm_module.dart';
import 'package:flutterastest/llm/llm_service.dart';
import 'package:flutterastest/parser/parser_module.dart';
import 'package:flutterastest/analysis/analysis_module.dart';
import 'package:flutterastest/pkg/pkg_module.dart';
import 'package:flutterastest/prompt_builder/prompt_module.dart';
import 'package:flutterastest/prompt_optimizer/prompt_optimizer_module.dart';
import 'package:flutterastest/mutation/mutation_module.dart';
import 'package:flutterastest/reflection/reflection_module.dart';

import 'contracts/pipeline_module.dart';
import 'pipeline_stage.dart';
import 'execution_trace.dart';
import 'module_registry.dart';
import 'pipeline_context.dart';
import 'pipeline_exception.dart';
import 'pipeline_result.dart';

class PipelineOrchestrator {
  PipelineOrchestrator({
    ModuleRegistry? registry,
    LlmService? llmService,
    this.requestInterval,
  })  : _registry = registry ?? ModuleRegistry(),
        _llmService = llmService;

  final Logger _logger = Logger('PipelineOrchestrator');
  Duration? _cpuAtStart;

  /// Early stages print long analysis tables; they stay in run.log unless
  /// --verbose is given.
  bool _quietStage = false;

  static const _quietStages = {
    PipelineStage.parser,
    PipelineStage.analysis,
    PipelineStage.knowledgeGraph,
    PipelineStage.contextBuilder,
    PipelineStage.promptBuilder,
  };

  static const _stageTitles = {
    PipelineStage.parser: 'Parsed the project',
    PipelineStage.analysis: 'Analysed screens',
    PipelineStage.knowledgeGraph: 'Built the knowledge graph',
    PipelineStage.contextBuilder: 'Selected context',
    PipelineStage.promptBuilder: 'Prepared prompts',
  };
  final ModuleRegistry _registry;

  /// Injected LLM; when null, Gemini is used with the key from the environment.
  final LlmService? _llmService;

  /// Overrides the run's pause between LLM calls.
  final Duration? requestInterval;

  Future<PipelineResult> start({
    required String projectPath,
    required bool verbose,
    bool promptsOnly = false,
    ExperimentConfig config = const ExperimentConfig(),
    String? flutter,
  }) {
    final resolved = config.resolvedFor(projectPath);
    final command = FlutterCommand.resolve(projectPath, override: flutter);
    final log = StringBuffer();
    return runZoned(
      () => _run(projectPath, verbose, promptsOnly, resolved, log, command),
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
        log.writeln(line);
        if (verbose || !_quietStage) parent.print(zone, line);
      }),
    );
  }

  /// Writes the records of Doc 16.13 next to the run's other artifacts.
  Future<void> _writeRecords(PipelineContext context, ExperimentConfig config, StringBuffer log,
      Duration total, FlutterCommand command) async {
    final directory = Directory(config.runDirectory);
    if (!directory.existsSync()) return;
    // The folder holds generated code and reports, not project source.
    final root = config.outputRoot;
    if (config.installTests && root != null) {
      await File(p.join(root, '.gitignore')).writeAsString('*\n');
    }
    const encoder = JsonEncoder.withIndent('  ');
    final analysis = context.get<AnalysisResult>();
    final graph = context.get<KnowledgeGraph>();
    final screens = analysis?.screenContexts.length ?? 0;

    await File(p.join(directory.path, 'run.log')).writeAsString(log.toString());
    await File(p.join(directory.path, 'environment.json')).writeAsString(encoder.convert({
      ...await const EnvironmentInfo().collect(projectPath: context.projectPath, command: command),
      'configuration': config.toJson(),
    }));
    await File(p.join(directory.path, 'execution_trace.json')).writeAsString(encoder.convert({
      'executionId': DateTime.now().toUtc().toIso8601String(),
      'experimentId': config.runName,
      'projectName': analysis?.projectInfo.packageName,
      'executionMode': config.mode.name,
      'frameworkVersion': '1.0.0',
      'flutter': command.toString(),
      'transitions': [
        for (final trace in context.traces)
          {
            'state': trace.stage.name,
            'startedAt': trace.startedAt.toUtc().toIso8601String(),
            'finishedAt': trace.finishedAt.toUtc().toIso8601String(),
            'durationMs': trace.finishedAt.difference(trace.startedAt).inMilliseconds,
            'status': trace.success ? 'success' : 'failed',
          },
      ],
      'modulesExecuted': context.metrics.modulesExecuted,
      'modulesFailed': context.metrics.modulesFailed,
    }));

    final cpuNow = await processCpuTime();
    final start = _cpuAtStart;
    final cpu = cpuNow == null || start == null ? null : cpuNow - start;
    await File(p.join(directory.path, 'performance.json')).writeAsString(encoder.convert({
      'totalMs': total.inMilliseconds,
      'toolCpuMs': cpu?.inMilliseconds,
      'toolCpuPercent':
          cpu == null ? null : cpuPercent(cpu, total, Platform.numberOfProcessors),
      'stagesMs': {
        for (final trace in context.traces)
          trace.stage.name: trace.finishedAt.difference(trace.startedAt).inMilliseconds,
      },
      'peakMemoryBytes': ProcessInfo.maxRss,
      'files': analysis?.totalFiles,
      'screens': screens,
      'pkgNodes': graph?.nodes.length,
      'pkgEdges': graph?.edges.length,
      'screensPerSecond': total.inMilliseconds == 0 ? 0 : screens * 1000 / total.inMilliseconds,
      'filesPerSecond':
          total.inMilliseconds == 0 ? 0 : (analysis?.totalFiles ?? 0) * 1000 / total.inMilliseconds,
      'widgets': analysis?.widgets.length,
      'callbacks': analysis?.callbacks.length,
      'navigationEdges': analysis?.navigation.length,
    }));
  }

  Future<PipelineResult> _run(String projectPath, bool verbose, bool promptsOnly,
      ExperimentConfig config, StringBuffer log, FlutterCommand command) async {
    final stopwatch = Stopwatch()..start();
    _cpuAtStart = await processCpuTime();

    final context = PipelineContext(
      projectPath: projectPath,
      verbose: verbose,
    )..put<ExperimentConfig>(config);

    _logger.info('');
    _logger.info('========================================');
    _logger.info('FlutterASTest');
    _logger.info('========================================');
    _logger.info('Project : $projectPath');
    _logger.info('Flutter : $command');
    _logger.info('Output  : ${config.outputRoot}');
    _logger.info('Mode    : ${config.mode.name}'
        '${config.reflect ? ' + reflection (max ${config.maxIterations} iterations)' : ''}'
        '${promptsOnly ? ' (prompts only)' : ''}');
    _logger.info('Verbose : $verbose');
    _logger.info('');

    _registerModules(promptsOnly: promptsOnly, config: config, command: command);

    try {
      for (final module in _registry.modules) {
        await _executeModule(
          module,
          context,
        );
      }

      stopwatch.stop();

      context.metrics.totalExecutionTime = stopwatch.elapsed;
      await _writeRecords(context, config, log, stopwatch.elapsed, command);

      _logger.info('');
      _logger.info('Pipeline completed successfully.');
      print('\nDone in ${(stopwatch.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s. '
          'Reports: ${config.runDirectory}');
      _logger.info(
        'Execution Time : ${context.metrics.totalExecutionTime.inMilliseconds} ms',
      );

      return PipelineResult(
        success: true,
        metrics: context.metrics,
      );
    } on LlmUnavailableException {
      await _writeRecords(context, config, log, stopwatch.elapsed, command);
      rethrow;
    } on PipelineException {
      await _writeRecords(context, config, log, stopwatch.elapsed, command);
      rethrow;
    } catch (e) {
      throw PipelineException(
        'Pipeline execution failed: $e',
      );
    }
  }

  Future<void> _executeModule(
    PipelineModule module,
    PipelineContext context,
  ) async {
    final started = DateTime.now();

    _logger.info(
      'Executing ${module.stage.name}...',
    );

    _quietStage = _quietStages.contains(module.stage);
    try {
      await module.execute(context);

      final finished = DateTime.now();
      if (_quietStage && !context.verbose) {
        _quietStage = false;
        print('[ok] ${_stageTitles[module.stage]} '
            '(${(finished.difference(started).inMilliseconds / 1000).toStringAsFixed(1)} s)');
      }

      context.metrics.modulesExecuted++;

      context.traces.add(
        ExecutionTrace(
          stage: module.stage,
          startedAt: started,
          finishedAt: finished,
          success: true,
        ),
      );
    } on LlmUnavailableException {
      rethrow;
    } catch (e) {
      _quietStage = false;
      final finished = DateTime.now();

      context.metrics.modulesFailed++;

      context.traces.add(
        ExecutionTrace(
          stage: module.stage,
          startedAt: started,
          finishedAt: finished,
          success: false,
        ),
      );

      throw PipelineException(
        '${module.stage.name} failed.\n$e',
      );
    }
  }

  void _registerModules({
    required bool promptsOnly,
    required ExperimentConfig config,
    required FlutterCommand command,
  }) {
    _registry.register(ParserModule());
    _registry.register(const AnalysisModule());
    _registry.register(PkgModule());
    _registry.register(const PromptModule());
    _registry.register(const PromptOptimizerModule());
    if (promptsOnly) return;

    final base = _llmService ?? createLlmService(config);
    final interval = requestInterval ??
        config.requestInterval ??
        (config.provider == 'local' ? Duration.zero : const Duration(seconds: 10));
    final guarded = CircuitBreakerLlmService(base);
    final llm = config.resume
        ? CachingLlmService(guarded, p.join(config.outputRoot ?? 'output', 'llm_cache', config.runName))
        : guarded;
    final runner = FlutterTestRunner(flutter: command);
    _registry.register(PreflightModule(runner: runner));
    _registry.register(LlmModule(llmService: llm, requestInterval: interval));
    _registry.register(ExecutorModule(runner: runner));
    if (config.reflect) {
      _registry.register(ReflectionModule(llmService: llm, requestInterval: interval));
    }
    if (config.mutation) _registry.register(MutationModule(runner: runner));
    _registry.register(EvaluationModule(llmService: llm));
  }
}
