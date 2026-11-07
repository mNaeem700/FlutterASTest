import 'dart:io';

import 'package:path/path.dart' as p;

import 'experiment_config.dart';
import 'models/screen_outcome.dart';

/// File layout of one run under `output/runs/<run>/`:
///
///     prompts/<Screen>_prompt.txt          prompt sent for iteration 0
///     tests/<Screen>_test.dart             latest test file of each screen
///     attempts/<Screen>/iteration_<k>.*    every attempt: response, code, lcov
///     results.json, results.csv            evaluation results
class RunArtifacts {
  RunArtifacts(ExperimentConfig config) : root = p.absolute(config.runDirectory);

  final String root;

  String testFile(String screen) => p.join(root, 'tests', '${screen}_test.dart');

  String _attempt(String screen, int iteration, String extension) =>
      p.join(root, 'attempts', screen, 'iteration_$iteration.$extension');

  String lcovFile(String screen, int iteration) => _attempt(screen, iteration, 'lcov.info');

  String get resultsJson => p.join(root, 'results.json');
  String get resultsCsv => p.join(root, 'results.csv');

  /// Saves the prompt, raw reply and extracted code of [attempt], and makes
  /// its code the screen's current test file.
  Future<void> saveAttempt(ScreenOutcome outcome, Attempt attempt, String prompt) async {
    final screen = outcome.screenName;
    final iteration = attempt.iteration;
    await _write(_attempt(screen, iteration, 'prompt.txt'), prompt);
    await _write(_attempt(screen, iteration, 'response.md'),
        attempt.generation.error == null ? attempt.generation.text : 'ERROR: ${attempt.generation.error}');
    await _write(_attempt(screen, iteration, 'dart'), attempt.code);
    await _write(testFile(screen), attempt.code);
  }

  static Future<void> _write(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }
}
