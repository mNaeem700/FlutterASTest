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
      _configureLogging(arguments.contains('--verbose'));

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

      return exitCode;
    } on CLIException catch (e) {
      stderr.writeln(e.message);
      return e.exitCode;
    } catch (e, stackTrace) {
      stderr.writeln('Error: ${_message(e)}');
      if (arguments.contains('--verbose')) {
        stderr.writeln(stackTrace);
      } else {
        stderr.writeln('Run again with --verbose for details, or run: flutterastest doctor');
      }
      return ExitCodes.unknownError;
    }
  }

  static String _message(Object error) =>
      '$error'.replaceFirst(RegExp(r'^(Bad state|Exception|PipelineException): '), '');

  void _configureLogging(bool verbose) {
    Logger.root.level = verbose ? Level.ALL : Level.WARNING;

    Logger.root.onRecord.listen((record) {
      stdout.writeln(
        '[${record.level.name}] ${record.message}',
      );
    });
  }

  void _printVersion() {
    stdout.writeln(
      'FlutterASTest 1.0.0',
    );
  }

  void _printHelp() {
    stdout.writeln('''
FlutterASTest

Usage:

flutterastest init                    first-time setup
flutterastest doctor [project]        check Flutter, project and LLM setup
flutterastest generate [project]      analyse the project, then write and run tests
                                      (also: analyse; default project: this folder)
flutterastest config list | get <k> | set <k> <v> | unset <k> |
                     set-key <provider> | remove-key <provider>
flutterastest batch <manifest.yaml>   all projects x setups x repetitions, resumable
flutterastest compare <runDir> <runDir> [...]   statistics between runs
flutterastest compare --batch-root <dir> <setup> <setup> [...]   across a batch
flutterastest accuracy <screen_contexts.json> <truth.json>   RQ1 precision/recall

Options:

--help
--version
--verbose
--prompts-only          analyse and write prompts, without LLM calls or test runs
--resume                replay saved LLM replies after an interruption
--output <dir>          results folder; the project stays unchanged (research runs)
--flutter <path>        Flutter to use instead of the detected one (project FVM, then PATH)
--config <file.yaml>    experiment settings; flags override it
--mode <m>              context: pkg (default), baseline (raw screen file),
                        file (screen + imported files), repository (all of lib/)
--ablation <a>          noPkgLinks, noContextBuilder, noPromptBuilder, noCoverageGuidance
--label <text>          run name suffix, e.g. rep2 for repetitions
--model <id>            LLM model id
--token-budget <n>      context limit in estimated tokens (default 8000)
--screen <name>         only this screen; repeat for more
--provider <p>          local (default, code stays on this machine), gemini, or openai
                        (any OpenAI-compatible API); cloud providers ask first
--accept-cloud          agree to send code to the cloud provider, for scripts
--temperature <t>, --top-p <p>, --seed <n>, --max-output-tokens <n>,
--request-timeout <s>   LLM settings; unset values use the provider default
--mutation              measure passing tests with mutation testing (slow)
--max-mutants <n>       mutants per screen (default 20)
--reflect               repair failing tests by feeding run results back to the LLM
--max-iterations <n>    maximum repair iterations with --reflect (default 5)
--test-timeout <s>      seconds before a flutter test run is killed (default 600)

By default reports go to <project>/.flutterastest/ and passing tests to
<project>/test/flutterastest/. Save your own key with: flutterastest config set-key <provider>
Privacy: PRIVACY.md. Terms: TERMS.md.
''');
  }
}
