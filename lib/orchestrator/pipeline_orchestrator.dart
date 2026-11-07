import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'package:flutterastest/evaluation/evaluation_module.dart';
import 'package:flutterastest/execution/executor_module.dart';
import 'package:flutterastest/execution/flutter_command.dart';
import 'package:flutterastest/execution/flutter_test_runner.dart';
import 'package:flutterastest/analysis/analysis_result.dart';
import 'package:flutterastest/experiment/environment_info.dart';
import 'package:flutterastest/experiment/experiment_config.dart';
import 'package:flutterastest/pkg/models/knowledge_graph.dart';
import 'package:path/path.dart' as p;
import 'package:flutterastest/llm/caching_llm_service.dart';
import 'package:flutterastest/llm/gemini_llm_service.dart';
import 'package:flutterastest/llm/llm_module.dart';
import 'package:flutterastest/llm/llm_service.dart';
import 'package:flutterastest/parser/parser_module.dart';
import 'package:flutterastest/analysis/analysis_module.dart';
import 'package:flutterastest/pkg/pkg_module.dart';
import 'package:flutterastest/prompt_builder/prompt_module.dart';
import 'package:flutterastest/prompt_optimizer/prompt_optimizer_module.dart';
import 'package:flutterastest/reflection/reflection_module.dart';

import 'contracts/pipeline_module.dart';
import 'execution_trace.dart';
import 'module_registry.dart';
import 'pipeline_context.dart';
import 'pipeline_exception.dart';
import 'pipeline_result.dart';

class PipelineOrchestrator {
  PipelineOrchestrator({
    ModuleRegistry? registry,
    LlmService? llmService,
    this.requestInterval = const Duration(seconds: 10),
  })  : _registry = registry ?? ModuleRegistry(),
        _llmService = llmService;

  final Logger _logger = Logger('PipelineOrchestrator');
  final ModuleRegistry _registry;

  /// Injected LLM; when null, Gemini is used with the key from the environment.
  final LlmService? _llmService;

  /// Pause between LLM calls, to respect provider rate limits.
  final Duration requestInterval;

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
        parent.print(zone, line);
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
    await File(p.join(directory.path, 'performance.json')).writeAsString(encoder.convert({
      'totalMs': total.inMilliseconds,
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
    }));
  }

  Future<PipelineResult> _run(String projectPath, bool verbose, bool promptsOnly,
      ExperimentConfig config, StringBuffer log, FlutterCommand command) async {
    final stopwatch = Stopwatch()..start();

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
      _logger.info(
        'Execution Time : ${context.metrics.totalExecutionTime.inMilliseconds} ms',
      );

      return PipelineResult(
        success: true,
        metrics: context.metrics,
      );
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

    try {
      await module.execute(context);

      final finished = DateTime.now();

      context.metrics.modulesExecuted++;

      context.traces.add(
        ExecutionTrace(
          stage: module.stage,
          startedAt: started,
          finishedAt: finished,
          success: true,
        ),
      );
    } catch (e) {
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

    final base = _llmService ??
        (config.model == null
            ? GeminiLlmService(apiKey: LlmModule.readApiKeyFromEnvironment())
            : GeminiLlmService(
                apiKey: LlmModule.readApiKeyFromEnvironment(), model: config.model!));
    final llm = config.resume
        ? CachingLlmService(base, p.join(config.outputRoot ?? 'output', 'llm_cache', config.runName))
        : base;
    final runner = FlutterTestRunner(flutter: command);
    _registry.register(PreflightModule(runner: runner));
    _registry.register(LlmModule(llmService: llm, requestInterval: requestInterval));
    _registry.register(ExecutorModule(runner: runner));
    if (config.reflect) {
      _registry.register(ReflectionModule(llmService: llm, requestInterval: requestInterval));
    }
    _registry.register(EvaluationModule(llmService: llm));
  }
}
