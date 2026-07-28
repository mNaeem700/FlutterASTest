import 'dart:io';

import 'cli_exception.dart';
import 'exit_codes.dart';
import 'models/cli_options.dart';

class CommandValidator {
  const CommandValidator();

  void validate(CLIOptions options) {
    if (options.help || options.version) {
      return;
    }

    if (options.command.isEmpty) {
      throw const CLIException(
        'No command specified.',
        ExitCodes.invalidArguments,
      );
    }

    switch (options.command) {
      case 'analyse':
        _validateAnalyse(options);
        break;

      default:
        throw CLIException(
          'Unknown command: ${options.command}',
          ExitCodes.invalidArguments,
        );
    }
  }

  void _validateAnalyse(CLIOptions options) {
    if (options.projectPath == null) {
      throw const CLIException(
        'Project path is required.',
        ExitCodes.invalidArguments,
      );
    }

    final directory = Directory(options.projectPath!);

    if (!directory.existsSync()) {
      throw CLIException(
        'Project not found: ${options.projectPath}',
        ExitCodes.invalidArguments,
      );
    }
  }
}
