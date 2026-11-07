import '../evaluation/extraction_accuracy.dart';
import '../evaluation/run_comparison.dart';
import '../experiment/batch_runner.dart';
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
          flutter: options.flutter,
        );

        break;

      case 'batch':
        await BatchRunner().runManifest(options.arguments.first);
        break;

      case 'compare':
        final root = options.batchRoot;
        if (root == null) {
          await const RunComparison().run(options.arguments);
        } else {
          await const RunComparison().runBatch(root, options.arguments);
        }
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
