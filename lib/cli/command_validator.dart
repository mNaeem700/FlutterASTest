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

      case 'batch':
        if (options.arguments.length != 1 || !File(options.arguments.first).existsSync()) {
          throw const CLIException(
              'batch needs an existing manifest file.', ExitCodes.invalidArguments);
        }
        break;

      case 'compare':
        if (options.arguments.length < 2) {
          throw const CLIException(
              'compare needs at least two run directories.', ExitCodes.invalidArguments);
        }
        break;

      case 'accuracy':
        if (options.arguments.length != 2) {
          throw const CLIException(
              'accuracy needs the screen contexts file and the ground truth file.',
              ExitCodes.invalidArguments);
        }
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
    final pubspec = File('${directory.path}${Platform.pathSeparator}pubspec.yaml');
    if (directory.existsSync() && !pubspec.existsSync()) {
      throw CLIException(
        'Not a Flutter project (no pubspec.yaml): ${options.projectPath}',
        ExitCodes.invalidArguments,
      );
    }

    if (!directory.existsSync()) {
      throw CLIException(
        'Project not found: ${options.projectPath}',
        ExitCodes.invalidArguments,
      );
    }
  }
}
