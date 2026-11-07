import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../llm/llm_service.dart';
import '../llm/llm_settings.dart';
import '../orchestrator/pipeline_orchestrator.dart';
import 'experiment_config.dart';

/// One run of a batch: which project, with which settings.
class BatchItem {
  const BatchItem({required this.project, required this.config, this.flutter});

  final String project;
  final ExperimentConfig config;
  final String? flutter;

  String get id => '${p.basename(project)}/${config.runName}';
}

/// Runs every project × setup × repetition from a YAML manifest, one by one.
///
/// A finished run is skipped when the batch is started again, and an
/// unfinished one replays its saved LLM replies, so an interrupted batch
/// repeats no LLM call. A run that fails is recorded and the batch goes on.
///
/// ```yaml
/// output: output/benchmark
/// repetitions: 3
/// projects:
///   - D:\apps\app_one
///   - {path: D:\apps\app_two, flutter: C:\sdks\3.47\bin\flutter.bat}
/// runs:
///   - {mode: baseline}
///   - {mode: pkg}
///   - {mode: pkg, reflect: true}
///   - {mode: pkg, ablation: noPkgLinks}
/// ```
class BatchRunner {
  BatchRunner({this.llmService, this.requestInterval = const Duration(seconds: 10)});

  /// Injected LLM; when null, each run uses the default service.
  final LlmService? llmService;
  final Duration requestInterval;

  static List<BatchItem> parse(String yamlText) {
    final yaml = loadYaml(yamlText);
    if (yaml is! YamlMap || yaml['projects'] is! YamlList || yaml['runs'] is! YamlList) {
      throw const FormatException('The manifest needs "projects" and "runs" lists.');
    }
    final output = p.normalize(p.absolute('${yaml['output'] ?? 'output/benchmark'}'));
    final repetitions = (yaml['repetitions'] as int?) ?? 1;

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

  static bool isComplete(BatchItem item) =>
      File(p.join(item.config.runDirectory, 'results.json')).existsSync();

  Future<void> runManifest(String path) async {
    final items = parse(File(path).readAsStringSync());
    final status = <String, String>{};
    var done = 0;

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
        await PipelineOrchestrator(llmService: llmService, requestInterval: requestInterval).start(
          projectPath: item.project,
          verbose: false,
          config: item.config,
          flutter: item.flutter,
        );
        status[item.id] = 'completed';
      } on Exception catch (e) {
        print('$progress: FAILED: $e');
        status[item.id] = 'failed: $e';
      } on StateError catch (e) {
        print('$progress: FAILED: $e');
        status[item.id] = 'failed: $e';
      }
    }

    final outcome = const JsonEncoder.withIndent('  ').convert(status);
    if (items.isNotEmpty) {
      final root = p.dirname(items.first.config.outputRoot!);
      await File(p.join(root, 'batch_status.json')).writeAsString(outcome);
      print('Batch status: ${p.join(root, 'batch_status.json')}');
    }
    final failed = status.values.where((s) => s.startsWith('failed')).length;
    print('Batch finished: ${items.length - failed} of ${items.length} runs complete, $failed failed.');
  }
}
