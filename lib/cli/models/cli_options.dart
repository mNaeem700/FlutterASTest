import 'package:meta/meta.dart';

import '../../experiment/experiment_config.dart';

@immutable
class CLIOptions {
  final String command;

  final String? projectPath;

  final bool verbose;

  final bool help;

  final bool version;

  /// Stop after writing prompts: no LLM calls and no test execution.
  final bool promptsOnly;

  /// Context mode, reflection and execution settings of the run.
  final ExperimentConfig experiment;

  /// Positional arguments after the command.
  final List<String> arguments;

  /// Flutter executable to use instead of the detected one.
  final String? flutter;

  const CLIOptions({
    required this.command,
    required this.projectPath,
    required this.verbose,
    required this.help,
    required this.version,
    this.promptsOnly = false,
    this.experiment = const ExperimentConfig(),
    this.arguments = const [],
    this.flutter,
  });
}
