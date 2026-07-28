import 'execution_metrics.dart';

class PipelineResult {
  PipelineResult({
    required this.success,
    required this.metrics,
  });

  final bool success;

  final ExecutionMetrics metrics;
}
