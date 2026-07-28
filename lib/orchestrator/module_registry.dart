import 'contracts/pipeline_module.dart';

class ModuleRegistry {
  final List<PipelineModule> _modules = [];

  void register(
    PipelineModule module,
  ) {
    _modules.add(module);
  }

  List<PipelineModule> get modules => List.unmodifiable(_modules);
}
