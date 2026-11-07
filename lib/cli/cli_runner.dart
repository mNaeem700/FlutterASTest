import '../evaluation/extraction_accuracy.dart';
import '../evaluation/run_comparison.dart';
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
          promptsOnly: options.promptsOnly,
          config: options.experiment,
        );

        break;

      case 'compare':
        await const RunComparison().run(options.arguments);
        break;

      case 'accuracy':
        await const ExtractionAccuracy().run(options.arguments[0], options.arguments[1]);
        break;

      default:
        throw UnsupportedError(
          'Unsupported command: ${options.command}',
        );
    }
  }
}
