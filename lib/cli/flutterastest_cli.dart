import 'dart:io';

import 'package:logging/logging.dart';

import 'cli_exception.dart';
import 'cli_runner.dart';
import 'command_parser.dart';
import 'command_validator.dart';
import 'exit_codes.dart';

class FlutterASTestCLI {
  FlutterASTestCLI({
    CommandParser? parser,
    CommandValidator? validator,
    CLIRunner? runner,
  })  : _parser = parser ?? CommandParser(),
        _validator = validator ?? const CommandValidator(),
        _runner = runner ?? const CLIRunner();

  final CommandParser _parser;

  final CommandValidator _validator;

  final CLIRunner _runner;

  Future<int> execute(List<String> arguments) async {
    try {
      _configureLogging();

      final options = _parser.parse(arguments);

      if (options.help) {
        _printHelp();
        return ExitCodes.success;
      }

      if (options.version) {
        _printVersion();
        return ExitCodes.success;
      }

      _validator.validate(options);

      await _runner.run(options);

      return ExitCodes.success;
    } on CLIException catch (e) {
      stderr.writeln(e.message);
      return e.exitCode;
    } catch (e, stackTrace) {
      Logger.root.severe(
        'Unhandled exception',
        e,
        stackTrace,
      );

      stderr.writeln(e);

      return ExitCodes.unknownError;
    }
  }

  void _configureLogging() {
    Logger.root.level = Level.ALL;

    Logger.root.onRecord.listen((record) {
      stdout.writeln(
        '[${record.level.name}] ${record.message}',
      );
    });
  }

  void _printVersion() {
    stdout.writeln(
      'FlutterASTest v1.0.0',
    );
  }

  void _printHelp() {
    stdout.writeln('''
FlutterASTest

Usage:

flutterastest analyse <project>

Options:

--help
--version
--verbose
''');
  }
}
