import 'dart:async';

import 'contracts/pipeline_module.dart';
import 'pipeline_context.dart';
import 'pipeline_stage.dart';

class DummyModule implements PipelineModule {
  @override
  PipelineStage get stage => PipelineStage.configuration;

  @override
  Future<void> execute(
    PipelineContext context,
  ) async {
    await Future.delayed(
      const Duration(milliseconds: 300),
    );

    print(
      'Configuration initialized.',
    );
  }
}
