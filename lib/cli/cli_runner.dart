import '../orchestrator/pipeline_orchestrator.dart';
import 'models/cli_options.dart';

class CLIRunner {
  const CLIRunner();

  Future<void> run(CLIOptions options) async {
    switch (options.command) {
      case 'analyse':
        final orchestrator = PipelineOrchestrator();

        await orchestrator.start(
          projectPath: options.projectPath!,
          verbose: options.verbose,
        );

        break;

      default:
        throw UnsupportedError(
          'Unsupported command: ${options.command}',
        );
    }
  }
}
