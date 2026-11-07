import 'dart:io';

import '../evaluation/extraction_accuracy.dart';
import '../evaluation/run_comparison.dart';
import '../experiment/batch_runner.dart';
import '../orchestrator/pipeline_orchestrator.dart';
import '../product/product_commands.dart';
import '../product/user_config.dart';

import 'models/cli_options.dart';

class CLIRunner {
  const CLIRunner();

  Future<void> run(CLIOptions options) async {
    switch (options.command) {
      case 'analyse':
        if (!options.promptsOnly) {
          const CloudConsent().ensure(options.experiment.provider,
              accepted: options.acceptCloud, user: UserConfig.load());
        }
        final orchestrator = PipelineOrchestrator();

        await orchestrator.start(
          projectPath: options.projectPath!,
          verbose: options.verbose,
          promptsOnly: options.promptsOnly,
          config: options.experiment,
          flutter: options.flutter,
        );

        break;

      case 'targets':
        await const TargetLister().run(options.projectPath!, unit: options.unit);
        break;

      case 'config':
        const ConfigCommand().run(options.arguments, UserConfig.load());
        break;

      case 'doctor':
        exitCode = await const Doctor().run(
          options.projectPath!,
          UserConfig.load(),
          provider: options.experiment.provider,
          model: options.experiment.model,
          config: options.experiment,
          testLlm: options.testLlm,
        );
        break;

      case 'init':
        exitCode = await const InitCommand().run(options.projectPath!, UserConfig.load());
        break;

      case 'batch':
        if (options.plan) {
          exitCode = await BatchRunner().plan(options.arguments.first);
        } else {
          await BatchRunner().runManifest(options.arguments.first);
        }
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
