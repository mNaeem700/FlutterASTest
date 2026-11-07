import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'package:flutterastest/evaluation/evaluation_module.dart';
import 'package:flutterastest/execution/executor_module.dart';
import 'package:flutterastest/analysis/analysis_result.dart';
import 'package:flutterastest/experiment/environment_info.dart';
import 'package:flutterastest/experiment/experiment_config.dart';
import 'package:flutterastest/pkg/models/knowledge_graph.dart';
import 'package:path/path.dart' as p;
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
  }) {
    final log = StringBuffer();
    return runZoned(
      () => _run(projectPath, verbose, promptsOnly, config, log),
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
        log.writeln(line);
        parent.print(zone, line);
      }),
    );
  }

  /// Writes the records of Doc 16.13 next to the run's other artifacts.
  Future<void> _writeRecords(
      PipelineContext context, ExperimentConfig config, StringBuffer log, Duration total) async {
    final directory = Directory(config.runDirectory);
    if (!directory.existsSync()) return;
    const encoder = JsonEncoder.withIndent('  ');
    final analysis = context.get<AnalysisResult>();
    final graph = context.get<KnowledgeGraph>();
    final screens = analysis?.screenContexts.length ?? 0;

    await File(p.join(directory.path, 'run.log')).writeAsString(log.toString());
    await File(p.join(directory.path, 'environment.json')).writeAsString(encoder.convert({
      ...await const EnvironmentInfo().collect(projectPath: context.projectPath),
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
      ExperimentConfig config, StringBuffer log) async {
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
    _logger.info('Mode    : ${config.mode.name}'
        '${config.reflect ? ' + reflection (max ${config.maxIterations} iterations)' : ''}'
        '${promptsOnly ? ' (prompts only)' : ''}');
    _logger.info('Verbose : $verbose');
    _logger.info('');

    _registerModules(promptsOnly: promptsOnly, config: config);

    try {
      for (final module in _registry.modules) {
        await _executeModule(
          module,
          context,
        );
      }

      stopwatch.stop();

      context.metrics.totalExecutionTime = stopwatch.elapsed;
      await _writeRecords(context, config, log, stopwatch.elapsed);

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
      await _writeRecords(context, config, log, stopwatch.elapsed);
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

  void _registerModules({required bool promptsOnly, required ExperimentConfig config}) {
    _registry.register(ParserModule());
    _registry.register(const AnalysisModule());
    _registry.register(PkgModule());
    _registry.register(const PromptModule());
    _registry.register(const PromptOptimizerModule());
    if (promptsOnly) return;

    final llm = _llmService ??
        (config.model == null
            ? GeminiLlmService(apiKey: LlmModule.readApiKeyFromEnvironment())
            : GeminiLlmService(
                apiKey: LlmModule.readApiKeyFromEnvironment(), model: config.model!));
    _registry.register(PreflightModule());
    _registry.register(LlmModule(llmService: llm, requestInterval: requestInterval));
    _registry.register(ExecutorModule());
    if (config.reflect) {
      _registry.register(ReflectionModule(llmService: llm, requestInterval: requestInterval));
    }
    _registry.register(EvaluationModule(llmService: llm));
  }
}
