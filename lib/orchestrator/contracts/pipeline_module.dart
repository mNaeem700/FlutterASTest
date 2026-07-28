import '../pipeline_context.dart';
import '../pipeline_stage.dart';

abstract interface class PipelineModule {
  PipelineStage get stage;

  Future<void> execute(
    PipelineContext context,
  );
}
