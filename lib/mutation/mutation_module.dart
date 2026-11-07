import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/analysis_result.dart';
import '../execution/flutter_test_runner.dart';
import '../experiment/experiment_config.dart';
import '../experiment/models/screen_outcome.dart';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import 'mutator.dart';

/// Mutation score of one generated test file (Doc 16.5): how many injected
/// faults its tests detect. Stronger evidence of correctness than pass rate.
class MutationResult {
  const MutationResult({required this.killed, required this.survived, required this.invalid});

  final int killed;

  /// Mutants the tests did not detect, as `operator@line:offset`.
  final List<String> survived;

  /// Mutants that did not compile; they say nothing about the tests.
  final int invalid;

  double get score {
    final valid = killed + survived.length;
    return valid == 0 ? 0 : killed / valid;
  }

  Map<String, dynamic> toJson() => {
        'killed': killed,
        'survived': survived.length,
        'invalid': invalid,
        'score': double.parse(score.toStringAsFixed(4)),
        'survivedMutants': survived,
      };
}

/// Runs mutation testing on a temporary copy of the project, so the
/// developer's source files are never changed. Only passing test files are
/// tested; a failing file cannot detect anything.
class MutationModule implements PipelineModule {
  MutationModule({required this.runner, this.mutator = const Mutator()});

  final FlutterTestRunner runner;
  final Mutator mutator;

  /// Not needed by `flutter test` on the host, and often large.
  static const _skipped = {
    'build', '.git', '.idea', '.vscode', 'android', 'ios', 'macos', 'windows', 'linux', 'web',
    '.flutterastest', 'coverage', 'flutter_build',
  };

  @override
  PipelineStage get stage => PipelineStage.mutation;

  static void copyProject(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final entity in from.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (_skipped.contains(name)) continue;
      final target = p.join(to.path, name);
      if (entity is Directory) {
        copyProject(entity, Directory(target));
      } else if (entity is File) {
        entity.copySync(target);
      }
    }
  }

  @override
  Future<void> execute(PipelineContext context) async {
    final config = context.get<ExperimentConfig>() ?? const ExperimentConfig();
    final outcomes = context.get<List<ScreenOutcome>>() ?? const [];
    final analysis = context.get<AnalysisResult>();
    final passing = [for (final o in outcomes) if (o.best?.run?.allPassed ?? false) o];

    print('\nMutation testing (${passing.length} passing test files, '
        'max ${config.maxMutants} mutants each)...');
    print('--------------------------------------------------');
    if (passing.isEmpty || analysis == null) return;

    final workspace = Directory.systemTemp.createTempSync('flutterastest_mutation');
    try {
      copyProject(Directory(context.projectPath), workspace);
      final lcov = p.join(workspace.path, '.mutation.lcov');

      for (final outcome in passing) {
        final screen = analysis.screenContexts.where((s) => s.name == outcome.screenName).firstOrNull;
        if (screen == null) continue;
        final file = File(p.join(workspace.path, screen.relativePath));
        final original = file.readAsStringSync();
        final mutants = mutator.generate(
          original,
          classes: {screen.name, if (screen.stateClassName != null) screen.stateClassName!},
          limit: config.maxMutants,
        );

        var killed = 0, invalid = 0;
        final survived = <String>[];
        for (final mutant in mutants) {
          file.writeAsStringSync(mutant.apply(original));
          final run = await runner.run(
            projectPath: workspace.path,
            screenName: outcome.screenName,
            screenFile: outcome.screenFile,
            code: outcome.best!.code,
            lcovPath: lcov,
            timeout: config.testTimeout,
            collectCoverage: false,
          );
          if (run.timedOut) {
            killed++;
          } else if (!run.compiled) {
            invalid++;
          } else if (run.allPassed) {
            survived.add(mutant.id);
          } else {
            killed++;
          }
        }
        file.writeAsStringSync(original);

        final result = MutationResult(killed: killed, survived: survived, invalid: invalid);
        outcome.best!.mutation = result;
        print('${outcome.screenName.padRight(32)} ${(result.score * 100).toStringAsFixed(1)}% '
            '($killed killed, ${survived.length} survived, $invalid invalid)');
      }
    } finally {
      workspace.deleteSync(recursive: true);
    }
  }
}
