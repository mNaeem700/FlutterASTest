import 'dart:async';

import 'package:flutterastest/orchestrator/dummy_module.dart';
import 'package:flutterastest/parser/parser_module.dart';
import 'package:logging/logging.dart';

import 'contracts/pipeline_module.dart';
import 'execution_trace.dart';
import 'module_registry.dart';
import 'pipeline_context.dart';
import 'pipeline_exception.dart';
import 'pipeline_result.dart';

class PipelineOrchestrator {
  PipelineOrchestrator({
    ModuleRegistry? registry,
  }) : _registry = registry ?? ModuleRegistry();

  final Logger _logger = Logger('PipelineOrchestrator');

  final ModuleRegistry _registry;

  Future<PipelineResult> start({
    required String projectPath,
    required bool verbose,
  }) async {
    final stopwatch = Stopwatch()..start();

    final context = PipelineContext(
      projectPath: projectPath,
      verbose: verbose,
    );

    _logger.info('');
    _logger.info('========================================');
    _logger.info('FlutterASTest');
    _logger.info('========================================');
    _logger.info('Project : $projectPath');
    _logger.info('Verbose : $verbose');
    _logger.info('');

    _registerModules();

    try {
      for (final module in _registry.modules) {
        await _executeModule(
          module,
          context,
        );
      }

      stopwatch.stop();

      context.metrics.totalExecutionTime = stopwatch.elapsed;

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

  void _registerModules() {
    _registry.register(
      ParserModule(),
    );
  }
}
