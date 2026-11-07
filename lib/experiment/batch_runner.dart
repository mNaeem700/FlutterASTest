import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../execution/flutter_command.dart';
import '../execution/flutter_test_runner.dart';
import '../llm/circuit_breaker_llm_service.dart';
import '../llm/llm_service.dart';
import '../llm/llm_settings.dart';
import '../orchestrator/pipeline_orchestrator.dart';
import 'experiment_config.dart';

/// One run of a batch: which project, with which settings.
class BatchItem {
  const BatchItem({required this.project, required this.config, this.flutter, this.pubGet = false});

  final String project;
  final ExperimentConfig config;
  final String? flutter;

  /// Run `flutter pub get` first, for freshly cloned apps.
  final bool pubGet;

  String get id => '${p.basename(project)}/${config.runName}';
}

/// Runs every project × setup × repetition from a YAML manifest, one by one.
///
/// A finished run is skipped when the batch is started again, and an
/// unfinished one replays its saved LLM replies, so an interrupted batch
/// repeats no LLM call. A run that fails is recorded and the batch goes on;
/// when the LLM itself is unavailable the batch stops, because every later run
/// would fail too. See `benchmark/manifest.example.yaml`.
class BatchRunner {
  BatchRunner({this.llmService, this.requestInterval});

  /// Injected LLM; when null, each run uses the configured provider.
  final LlmService? llmService;
  final Duration? requestInterval;

  static List<BatchItem> parse(String yamlText) {
    final yaml = loadYaml(yamlText);
    if (yaml is! YamlMap || yaml['projects'] is! YamlList || yaml['runs'] is! YamlList) {
      throw const FormatException('The manifest needs "projects" and "runs" lists.');
    }
    final output = p.normalize(p.absolute('${yaml['output'] ?? 'output/benchmark'}'));
    final repetitions = (yaml['repetitions'] as int?) ?? 1;
    final pubGet = yaml['pubGet'] as bool? ?? false;

    return [
      for (final project in yaml['projects'] as YamlList)
        for (final run in yaml['runs'] as YamlList)
          for (var rep = 1; rep <= repetitions; rep++)
            () {
              final path = project is YamlMap ? '${project['path']}' : '$project';
              final absolute = p.normalize(p.absolute(path));
              return BatchItem(
                project: absolute,
                flutter: project is YamlMap ? project['flutter'] as String? : null,
                pubGet: pubGet,
                config: _config(run as YamlMap, yaml).copyWith(
                  outputRoot: p.join(output, p.basename(absolute)),
                  label: repetitions > 1 ? 'rep$rep' : null,
                  resume: true,
                ),
              );
            }(),
    ];
  }

  static ExperimentConfig _config(YamlMap run, YamlMap manifest) => ExperimentConfig(
        mode: ContextMode.values.byName('${run['mode'] ?? 'pkg'}'),
        ablation: Ablation.values.byName('${run['ablation'] ?? 'none'}'),
        reflect: run['reflect'] as bool? ?? false,
        maxIterations:
            manifest['maxIterations'] as int? ?? ExperimentConfig.defaultMaxIterations,
        tokenBudget: manifest['tokenBudget'] as int? ?? 8000,
        testTimeout: Duration(seconds: manifest['testTimeoutSeconds'] as int? ?? 600),
        provider: manifest['provider'] as String? ?? 'gemini',
        mutation: manifest['mutation'] as bool? ?? false,
        maxMutants: manifest['maxMutants'] as int? ?? 20,
        maxScreens: manifest['screensPerApp'] as int?,
        requestInterval: manifest['requestIntervalSeconds'] == null
            ? null
            : Duration(seconds: manifest['requestIntervalSeconds'] as int),
        llm: LlmSettings(
          temperature: (manifest['temperature'] as num?)?.toDouble(),
          topP: (manifest['topP'] as num?)?.toDouble(),
          seed: manifest['seed'] as int?,
          maxOutputTokens: manifest['maxOutputTokens'] as int?,
          requestTimeout: manifest['requestTimeoutSeconds'] == null
              ? null
              : Duration(seconds: manifest['requestTimeoutSeconds'] as int),
        ),
        flakyRetries: manifest['flakyRetries'] as int? ?? 2,
        model: manifest['model'] as String?,
      );

  /// A run counts as complete only when every screen got a reply from the LLM.
  /// Otherwise the batch runs it again: saved replies are replayed and only the
  /// failed screens are requested.
  static bool isComplete(BatchItem item) {
    final file = File(p.join(item.config.runDirectory, 'results.json'));
    if (!file.existsSync()) return false;
    try {
      final summary = (jsonDecode(file.readAsStringSync()) as Map)['summary'] as Map;
      return summary['generated'] == summary['screens'];
    } on Object {
      return false;
    }
  }

  static Future<String?> _pubGet(BatchItem item) async {
    final command = FlutterCommand.resolve(item.project, override: item.flutter);
    final result = await command.runIn(['pub', 'get'], item.project);
    return result.exitCode == 0 ? null : '${result.stderr}'.trim().split('\n').take(3).join(' ');
  }

  /// Checks every app without calling the LLM: which ones can run, how many
  /// screens they have, and how many LLM calls the batch needs at least.
  Future<int> plan(String path) async {
    final items = parse(File(path).readAsStringSync());
    final projects = {for (final item in items) item.project: item};
    final runsPerProject = projects.isEmpty ? 0 : items.length ~/ projects.length;
    var totalCalls = 0;
    var ready = 0;

    print('App'.padRight(34) + 'Status'.padRight(12) + 'Screens'.padRight(10) + 'Min calls');
    for (final item in projects.values) {
      final name = p.basename(item.project);
      String? problem;
      if (!File(p.join(item.project, 'pubspec.yaml')).existsSync()) {
        problem = 'no pubspec.yaml';
      } else if (item.pubGet) {
        problem = await _pubGet(item);
      }
      final runner =
          FlutterTestRunner(flutter: FlutterCommand.resolve(item.project, override: item.flutter));
      problem ??= await runner.preflight(item.project, timeout: const Duration(minutes: 5));

      var screens = 0;
      if (problem == null) {
        final root = p.join(p.dirname(item.config.outputRoot!), '.plan', name);
        await PipelineOrchestrator().start(
          projectPath: item.project,
          verbose: false,
          promptsOnly: true,
          config: item.config.copyWith(outputRoot: root),
          flutter: item.flutter,
        );
        final contexts = File(p.join(root, 'runs', item.config.runName, 'prompts'));
        screens = Directory(contexts.path).listSync().length;
        Directory(root).deleteSync(recursive: true);
        ready++;
        totalCalls += screens * runsPerProject;
      }
      print('${name.padRight(34)}${(problem == null ? 'ready' : 'NOT READY').padRight(12)}'
          '${'$screens'.padRight(10)}${screens * runsPerProject}');
      if (problem != null) print('  ${problem.split('\n').first}');
    }
    print('\n$ready of ${projects.length} apps are ready, $runsPerProject runs per app, '
        'at least $totalCalls LLM calls.\nReflection adds up to '
        '${items.isEmpty ? 0 : items.first.config.maxIterations} calls per failing screen.');
    return ready == projects.length ? 0 : 1;
  }

  Future<void> runManifest(String path) async {
    final items = parse(File(path).readAsStringSync());
    final status = <String, String>{};
    var done = 0;

    Future<void> saveStatus() async {
      if (items.isEmpty) return;
      final file = File(p.join(p.dirname(items.first.config.outputRoot!), 'batch_status.json'));
      file.parent.createSync(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(status));
    }

    for (final item in items) {
      done++;
      final progress = '[$done/${items.length}] ${item.id}';
      if (isComplete(item)) {
        print('$progress: already complete, skipped');
        status[item.id] = 'skipped';
        continue;
      }
      print('$progress: running');
      try {
        if (item.pubGet) {
          final problem = await _pubGet(item);
          if (problem != null) throw StateError('flutter pub get failed: $problem');
        }
        await PipelineOrchestrator(llmService: llmService, requestInterval: requestInterval).start(
          projectPath: item.project,
          verbose: false,
          config: item.config,
          flutter: item.flutter,
        );
        status[item.id] = isComplete(item) ? 'completed' : 'incomplete: some screens got no reply';
      } on LlmUnavailableException catch (e) {
        status[item.id] = 'stopped: $e';
        await saveStatus();
        print('\n$progress: $e');
        rethrow;
      } on Exception catch (e) {
        print('$progress: FAILED: $e');
        status[item.id] = 'failed: $e';
      } on StateError catch (e) {
        print('$progress: FAILED: $e');
        status[item.id] = 'failed: $e';
      }
      await saveStatus();
    }

    await saveStatus();
    final failed = status.values.where((s) => s.startsWith('failed') || s.startsWith('incomplete')).length;
    print('Batch finished: ${items.length - failed} of ${items.length} runs complete, $failed not.');
    if (items.isNotEmpty) {
      print('Status: ${p.join(p.dirname(items.first.config.outputRoot!), 'batch_status.json')}');
    }
  }
}
