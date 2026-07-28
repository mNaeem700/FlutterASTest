import 'execution_metrics.dart';
import 'execution_trace.dart';

class PipelineContext {
  PipelineContext({
    required this.projectPath,
    required this.verbose,
  });

  final String projectPath;

  final bool verbose;

  final ExecutionMetrics metrics = ExecutionMetrics();

  final List<ExecutionTrace> traces = [];

  final Map<Type, Object> data = {};

  T? get<T>() {
    final value = data[T];

    if (value == null) {
      return null;
    }

    return value as T;
  }

  void put<T>(
    T value,
  ) {
    data[T] = value as Object;
  }
}
