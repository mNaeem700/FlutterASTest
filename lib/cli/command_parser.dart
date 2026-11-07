import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../experiment/experiment_config.dart';
import '../llm/llm_settings.dart';
import '../product/user_config.dart';
import 'cli_exception.dart';
import 'exit_codes.dart';
import 'models/cli_options.dart';

class CommandParser {
  CommandParser({UserConfig? user}) : _user = user ?? UserConfig.load();

  final UserConfig _user;

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
      )
      ..addFlag(
        'prompts-only',
        negatable: false,
      )
      ..addOption(
        'mode',
        allowed: [for (final mode in ContextMode.values) mode.name],
        defaultsTo: ContextMode.pkg.name,
      )
      ..addFlag(
        'reflect',
        negatable: false,
      )
      ..addOption(
        'max-iterations',
        defaultsTo: '${ExperimentConfig.defaultMaxIterations}',
      )
      ..addOption(
        'test-timeout',
        defaultsTo: '600',
      )
      ..addOption('config')
      ..addOption('ablation', allowed: [for (final a in Ablation.values) a.name])
      ..addOption('label')
      ..addOption('model')
      ..addOption('token-budget')
      ..addOption('output')
      ..addOption('flutter')
      ..addOption('batch-root')
      ..addFlag('resume', negatable: false)
      ..addFlag('mutation', negatable: false)
      ..addOption('max-mutants')
      ..addOption('provider', allowed: ['local', 'gemini', 'openai'])
      ..addFlag('accept-cloud', negatable: false)
      ..addOption('temperature')
      ..addOption('top-p')
      ..addOption('seed')
      ..addOption('max-output-tokens')
      ..addOption('request-timeout')
      ..addMultiOption('screen');

    final ArgResults result;
    try {
      result = parser.parse(arguments);
    } on FormatException catch (e) {
      throw CLIException(e.message, ExitCodes.invalidArguments);
    }

    final first = result.rest.isNotEmpty ? result.rest.first : '';
    final command = const {'analyze', 'generate'}.contains(first) ? 'analyse' : first;

    // The analyzer accepts only absolute, normalized paths, so `.`,
    // relative paths and forward slashes on Windows are normalized here.
    // Without a path, the project is the current folder.
    final project = result.rest.length > 1
        ? p.normalize(p.absolute(result.rest[1]))
        : (command == 'analyse' || command == 'doctor' || command == 'init'
            ? p.normalize(p.absolute('.'))
            : null);

    return CLIOptions(
      command: command,
      projectPath: project,
      verbose: result['verbose'],
      help: result['help'],
      version: result['version'],
      promptsOnly: result['prompts-only'],
      arguments: result.rest.skip(1).toList(),
      flutter: result['flutter'] as String?,
      batchRoot: result['batch-root'] as String?,
      acceptCloud: result['accept-cloud'] as bool,
      experiment: _experiment(result),
    );
  }

  /// The YAML file, if any, overridden by flags given on the command line.
  ExperimentConfig _experiment(ArgResults result) {
    final path = result['config'] as String?;
    if (path != null && !File(path).existsSync()) {
      throw CLIException('Config file not found: $path', ExitCodes.invalidArguments);
    }
    final base = path == null ? const ExperimentConfig() : ExperimentConfig.fromYaml(path);
    return base.copyWith(
      mode: result.wasParsed('mode') ? ContextMode.values.byName(result['mode'] as String) : null,
      reflect: result.wasParsed('reflect') ? true : null,
      maxIterations: result.wasParsed('max-iterations') ? _positiveInt(result, 'max-iterations') : null,
      testTimeout: result.wasParsed('test-timeout')
          ? Duration(seconds: _positiveInt(result, 'test-timeout'))
          : null,
      ablation: result.wasParsed('ablation')
          ? Ablation.values.byName(result['ablation'] as String)
          : null,
      label: result['label'] as String?,
      resume: result['resume'] as bool ? true : null,
      mutation: result['mutation'] as bool ? true : null,
      maxMutants: result.wasParsed('max-mutants') ? _positiveInt(result, 'max-mutants') : null,
      provider: result['provider'] as String? ?? (path == null ? _user['provider'] : null),
      screens: result.wasParsed('screen') ? (result['screen'] as List<String>).toSet() : null,
      llm: LlmSettings(
        temperature: _number(result, 'temperature') ?? base.llm.temperature,
        topP: _number(result, 'top-p') ?? base.llm.topP,
        seed: _number(result, 'seed')?.toInt() ?? base.llm.seed,
        maxOutputTokens: _number(result, 'max-output-tokens')?.toInt() ?? base.llm.maxOutputTokens,
        requestTimeout: result.wasParsed('request-timeout')
            ? Duration(seconds: _positiveInt(result, 'request-timeout'))
            : base.llm.requestTimeout,
      ),
      model: result['model'] as String?,
      outputRoot: result['output'] == null
          ? null
          : p.normalize(p.absolute(result['output'] as String)),
      tokenBudget: result.wasParsed('token-budget') ? _positiveInt(result, 'token-budget') : null,
    );
  }

  static double? _number(ArgResults result, String name) {
    if (!result.wasParsed(name)) return null;
    final value = double.tryParse(result[name] as String);
    if (value == null) {
      throw CLIException('--$name must be a number.', ExitCodes.invalidArguments);
    }
    return value;
  }

  static int _positiveInt(ArgResults result, String name) {
    final value = int.tryParse(result[name] as String);
    if (value == null || value < 1) {
      throw CLIException('--$name must be a positive whole number.', ExitCodes.invalidArguments);
    }
    return value;
  }
}
