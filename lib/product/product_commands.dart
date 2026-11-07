import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../cli/cli_exception.dart';
import '../cli/exit_codes.dart';
import '../execution/flutter_command.dart';
import '../experiment/experiment_config.dart';
import '../llm/llm_factory.dart';
import '../orchestrator/pipeline_orchestrator.dart';
import 'user_config.dart';

/// False for pipes, redirects and closed input, where asking the check itself
/// can throw.
bool _hasTerminal() {
  try {
    return stdin.hasTerminal;
  } on Exception {
    return false;
  }
}

/// A line of input, or null when there is no usable input. On Windows a
/// redirected input can report a terminal and only fail when read.
String? _readLine() {
  try {
    return stdin.readLineSync()?.trim();
  } on Exception {
    return null;
  }
}

/// Asks once before a cloud provider receives code, and remembers the answer.
/// A local model never needs this: nothing leaves the machine.
class CloudConsent {
  const CloudConsent();

  void ensure(String provider, {required bool accepted, required UserConfig user}) {
    if (provider == 'local' || accepted || user.cloudConsent(provider)) return;
    final noInput = CLIException(
      'Provider "$provider" sends your code to a cloud service. Pass --accept-cloud to '
      'agree, or use a local model with --provider local.',
      ExitCodes.invalidArguments,
    );
    if (!_hasTerminal()) throw noInput;
    stdout.write('\nProvider "$provider" sends parts of your source code to a cloud service, '
        'under that service\'s terms.\nA local model keeps your code on this machine '
        '(--provider local).\nContinue with "$provider"? [y/N] ');
    final line = _readLine();
    if (line == null) {
      stdout.writeln();
      throw noInput;
    }
    final answer = line.toLowerCase();
    if (answer != 'y' && answer != 'yes') {
      throw const CLIException('Cancelled. Nothing was sent.', ExitCodes.invalidArguments);
    }
    user.setCloudConsent(provider, true);
  }
}

/// `flutterastest config`: developer settings and their own API keys.
class ConfigCommand {
  const ConfigCommand();

  void run(List<String> arguments, UserConfig user) {
    final action = arguments.isEmpty ? 'list' : arguments.first;
    final rest = arguments.skip(1).toList();
    switch (action) {
      case 'list':
        final values = user.describe();
        if (values.isEmpty) stdout.writeln('No settings yet. Run: flutterastest init');
        values.forEach((key, value) => stdout.writeln('$key = $value'));
      case 'get' when rest.length == 1 && UserConfig.settings.contains(rest.first):
        stdout.writeln(user[rest.first] ?? '');
      case 'set' when rest.length == 2 && UserConfig.settings.contains(rest.first):
        user[rest.first] = rest[1];
        stdout.writeln('${rest.first} = ${rest[1]}');
      case 'unset' when rest.length == 1 && UserConfig.settings.contains(rest.first):
        user[rest.first] = null;
      case 'set-key' when rest.length == 1:
        // Read from the terminal, so the key never lands in shell history.
        final key = readApiKey(rest.first);
        if (key.isEmpty) {
          throw const CLIException(
              'No key found. Copy your API key, run this command again and press Enter.',
              ExitCodes.invalidArguments);
        }
        final problem = apiKeyProblem(key);
        if (problem != null) {
          throw CLIException('The key was not saved: $problem.', ExitCodes.invalidArguments);
        }
        user.setApiKey(rest.first, key);
        stdout.writeln('Saved key ${UserConfig.mask(key)} in ${user.file.path}');
      case 'remove-key' when rest.length == 1:
        user.setApiKey(rest.first, null);
        stdout.writeln('Removed the key for ${rest.first}.');
      default:
        throw CLIException(
          'Usage: flutterastest config list | get <k> | set <k> <v> | unset <k> | '
          'set-key <provider> | remove-key <provider>\nSettings: ${UserConfig.settings.join(', ')}',
          ExitCodes.invalidArguments,
        );
    }
  }

  /// Pasting into a hidden prompt can fail: some Windows consoles deliver
  /// Ctrl+V as a control character. So a copied key works with just Enter.
  static String readApiKey(String provider) => secretFrom(
        readSecret('API key for $provider (copy it, then paste or just press Enter): '),
        readClipboard,
      );

  /// The typed text without control characters, or else the clipboard.
  static String secretFrom(String typed, String Function() clipboard) {
    final clean = typed.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    return clean.isNotEmpty ? clean : clipboard().trim();
  }

  static String readClipboard() {
    final commands = Platform.isWindows
        ? const [
            ['powershell', '-NoProfile', '-Command', 'Get-Clipboard'],
          ]
        : Platform.isMacOS
            ? const [
                ['pbpaste'],
              ]
            : const [
                ['wl-paste', '--no-newline'],
                ['xclip', '-selection', 'clipboard', '-o'],
              ];
    for (final command in commands) {
      try {
        final result = Process.runSync(command.first, command.sublist(1));
        if (result.exitCode == 0) return '${result.stdout}';
      } on ProcessException {
        continue;
      }
    }
    return '';
  }

  static String readSecret(String prompt) {
    stdout.write(prompt);
    if (!_hasTerminal()) return _readLine() ?? '';
    try {
      stdin.echoMode = false;
    } on Exception {
      return _readLine() ?? '';
    }
    try {
      return _readLine() ?? '';
    } finally {
      stdin.echoMode = true;
      stdout.writeln();
    }
  }
}

class DoctorCheck {
  const DoctorCheck(this.name, this.ok, this.detail, {this.fix});

  final String name;
  final bool ok;
  final String detail;
  final String? fix;
}

/// `flutterastest doctor`: says what works and how to fix what does not.
class Doctor {
  const Doctor();

  Future<int> run(
    String projectPath,
    UserConfig user, {
    String? provider,
    String? model,
    ExperimentConfig? config,
    bool testLlm = false,
  }) async {
    final chosen = provider ?? user['provider'] ?? 'local';
    final chosenModel = model ?? user['model'];
    final checks = [
      DoctorCheck('Dart', true, Platform.version.split(' ').first),
      await _flutter(projectPath),
      _project(projectPath),
      if (chosen == 'local')
        await checkLocalServer(localBaseUrl(user), chosenModel)
      else
        _cloudKey(chosen, user),
      if (testLlm && config != null) await _llmCall(config),
    ];
    stdout.writeln('FlutterASTest doctor\n');
    for (final check in checks) {
      stdout.writeln('${check.ok ? '[ok]' : '[!!]'} ${check.name}: ${check.detail}');
      if (!check.ok && check.fix != null) stdout.writeln('     Fix: ${check.fix}');
    }
    final problems = checks.where((c) => !c.ok).length;
    stdout.writeln(problems == 0 ? '\nEverything is ready.' : '\n$problems problem(s) found.');
    return problems == 0 ? ExitCodes.success : ExitCodes.configurationError;
  }

  /// One small request with no project code in it: proves the key and the
  /// model work before a long run spends time.
  Future<DoctorCheck> _llmCall(ExperimentConfig config) async {
    try {
      final service = createLlmService(config);
      final reply = await service.generate('Reply with the single word OK.');
      return reply.succeeded
          ? DoctorCheck('LLM call', true, '${service.model} replied in ${reply.latencyMs} ms')
          : DoctorCheck('LLM call', false, '${service.model}: ${reply.error}',
              fix: 'Check the API key, the model name and the quota.');
    } on StateError catch (e) {
      return DoctorCheck('LLM call', false, e.message);
    }
  }

  Future<DoctorCheck> _flutter(String projectPath) async {
    final command = FlutterCommand.resolve(projectPath);
    try {
      final result = await command.run(['--version', '--machine']);
      final text = '${result.stdout}';
      final start = text.indexOf('{');
      if (result.exitCode != 0 || start < 0) throw const FormatException();
      final version = (jsonDecode(text.substring(start)) as Map)['frameworkVersion'];
      return DoctorCheck('Flutter', true, '$version (${command.source})');
    } on Exception {
      return DoctorCheck('Flutter', false, 'not found (${command.source})',
          fix: 'Install Flutter, or pass --flutter <path>.');
    }
  }

  DoctorCheck _project(String projectPath) {
    final hasPubspec = File(p.join(projectPath, 'pubspec.yaml')).existsSync();
    if (!hasPubspec) {
      return DoctorCheck('Project', false, 'no pubspec.yaml in $projectPath',
          fix: 'Run this inside a Flutter project.');
    }
    final resolved = File(p.join(projectPath, '.dart_tool', 'package_config.json')).existsSync();
    return DoctorCheck('Project', resolved, resolved ? projectPath : 'dependencies not resolved',
        fix: 'Run: flutter pub get');
  }

  DoctorCheck _cloudKey(String provider, UserConfig user) {
    final variable = provider == 'gemini' ? 'GEMINI_API_KEY' : 'OPENAI_API_KEY';
    final fromEnv = Platform.environment[variable]?.trim() ?? '';
    final key = fromEnv.isNotEmpty ? fromEnv : user.apiKey(provider);
    if (key == null || key.isEmpty) {
      return DoctorCheck('API key', false, 'no $provider key',
          fix: 'Run: flutterastest config set-key $provider');
    }
    final problem = apiKeyProblem(key);
    return DoctorCheck('API key', problem == null, problem ?? '$provider key found',
        fix: 'Run: flutterastest config set-key $provider');
  }

  /// Whether a local OpenAI-compatible server is up and has the model.
  static Future<DoctorCheck> checkLocalServer(String baseUrl, String? model) async {
    const name = 'Local model';
    const install = 'Install Ollama (https://ollama.com), then: ollama pull <model>';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/models'));
      final response = await request.close().timeout(const Duration(seconds: 5));
      final body = await response.transform(utf8.decoder).join();
      final data = (jsonDecode(body) as Map)['data'] as List? ?? const [];
      final models = [for (final m in data) '${(m as Map)['id']}'];
      if (model == null) {
        return DoctorCheck(name, false, 'server is up, no model chosen (available: ${models.join(', ')})',
            fix: 'Run: flutterastest config set model <name>');
      }
      return models.contains(model)
          ? DoctorCheck(name, true, '$model at $baseUrl')
          : DoctorCheck(name, false, '"$model" is not installed (available: ${models.join(', ')})',
              fix: 'Run: ollama pull $model');
    } on Exception {
      return DoctorCheck(name, false, 'no server at $baseUrl', fix: install);
    } finally {
      client.close(force: true);
    }
  }
}

/// `flutterastest targets`: what tests can be written for, as JSON, so a person
/// or the extension can choose one screen or class.
class TargetLister {
  const TargetLister();

  Future<void> run(String projectPath, {required bool unit}) async {
    final temp = Directory.systemTemp.createTempSync('flutterastest_targets');
    try {
      await runZoned(
        () => PipelineOrchestrator().start(
          projectPath: projectPath,
          verbose: false,
          promptsOnly: true,
          config: ExperimentConfig(outputRoot: temp.path),
        ),
        zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {}),
      );
      final analysis = p.join(temp.path, 'analysis');
      final List<dynamic> targets = unit
          ? jsonDecode(File(p.join(analysis, 'unit_targets.json')).readAsStringSync()) as List
          : (jsonDecode(File(p.join(analysis, 'screen_contexts.json')).readAsStringSync())
              as Map)['screens'] as List;
      stdout.writeln(jsonEncode([
        for (final target in targets) {'name': target['name'], 'file': target['filePath']},
      ]));
    } finally {
      temp.deleteSync(recursive: true);
    }
  }
}

/// `flutterastest init`: first-time setup.
class InitCommand {
  const InitCommand();

  Future<int> run(String projectPath, UserConfig user) async {
    if (!_hasTerminal()) {
      throw const CLIException(
          'init is interactive. Use "flutterastest config set" in scripts.', ExitCodes.invalidArguments);
    }
    stdout.writeln('FlutterASTest setup\n\n'
        '1. local   Your code stays on this machine (needs Ollama or similar).\n'
        '2. gemini  Google Gemini with your own API key. Code is sent to Google.\n'
        '3. openai  An OpenAI-compatible service with your own key. Code is sent to it.\n');
    stdout.write('Choose [1]: ');
    final choice = _readLine() ?? '';
    final provider = switch (choice) { '2' => 'gemini', '3' => 'openai', _ => 'local' };
    user['provider'] = provider;

    stdout.write('Model name${provider == 'local' ? ' (for example from "ollama list")' : ' (empty for default)'}: ');
    final model = _readLine() ?? '';
    user['model'] = model.isEmpty ? null : model;

    if (provider != 'local') {
      final key = ConfigCommand.readApiKey(provider);
      final problem = key.isEmpty ? null : apiKeyProblem(key);
      if (problem != null) {
        stdout.writeln('The key was not saved: $problem. Use: flutterastest config set-key $provider');
      } else if (key.isNotEmpty) {
        user.setApiKey(provider, key);
      }
      const CloudConsent().ensure(provider, accepted: false, user: user);
    }
    stdout.writeln();
    return const Doctor().run(projectPath, user);
  }
}
