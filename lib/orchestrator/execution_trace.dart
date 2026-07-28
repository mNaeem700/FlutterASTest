import 'pipeline_stage.dart';

class ExecutionTrace {
  ExecutionTrace({
    required this.stage,
    required this.startedAt,
    required this.finishedAt,
    required this.success,
  });

  final PipelineStage stage;

  final DateTime startedAt;

  final DateTime finishedAt;

  final bool success;

  Duration get duration => finishedAt.difference(startedAt);
}
