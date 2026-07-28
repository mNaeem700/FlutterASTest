import 'package:args/args.dart';

import 'models/cli_options.dart';

class CommandParser {
  CommandParser();

  CLIOptions parse(List<String> arguments) {
    final parser = ArgParser()
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
      )
      ..addFlag(
        'version',
        abbr: 'v',
        negatable: false,
      )
      ..addFlag(
        'verbose',
        negatable: false,
      );

    final result = parser.parse(arguments);

    final command = result.rest.isNotEmpty ? result.rest.first : '';

    final project = result.rest.length > 1 ? result.rest[1] : null;

    return CLIOptions(
      command: command,
      projectPath: project,
      verbose: result['verbose'],
      help: result['help'],
      version: result['version'],
    );
  }
}
