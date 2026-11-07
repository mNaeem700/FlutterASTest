import '../../evaluation/test_quality_analyzer.dart';
import '../../execution/models/test_run.dart';
import '../../llm/models/llm_response.dart';
import '../../mutation/mutation_module.dart';
import '../../reflection/failure_analyzer.dart';

/// One generated version of a screen's test file. Iteration 0 is the
/// initial generation; later iterations are reflection repairs.
class Attempt {
  Attempt({required this.iteration, required this.generation, required this.code});

  final int iteration;
  final LlmResponse generation;
  final String code;

  /// Set once the attempt has been executed.
  TestRun? run;

  /// Diagnosis of [run], set by the reflection loop.
  FailureAnalysis? analysis;

  /// Set when mutation testing ran on this attempt.
  MutationResult? mutation;

  late final TestQuality quality = const TestQualityAnalyzer().analyse(code);

  /// Passing, without ignoring errors to get there.
  bool get honestlyPassed => (run?.allPassed ?? false) && !quality.hidesErrors;

  Map<String, dynamic> toJson() => {
        'iteration': iteration,
        'generation': generation.toJson(),
        'quality': quality.toJson(),
        'analysis': analysis?.toJson(),
        if (mutation != null) 'mutation': mutation!.toJson(),
        'run': run?.toJson(),
      };
}

/// Everything that happened for one screen during a run.
class ScreenOutcome {
  ScreenOutcome({
    required this.screenName,
    required this.screenFile,
    required this.prompt,
  });

  final String screenName;
  final String screenFile;
  final String prompt;
  final List<Attempt> attempts = [];

  /// Why reflection stopped (Doc 15.20.2); null without reflection.
  String? stoppingReason;

  Attempt? get last => attempts.isEmpty ? null : attempts.last;

  /// The attempt that counts as the result: a repair can make a file worse, so
  /// this is the best executed attempt, not necessarily the latest.
  Attempt? get best {
    Attempt? best;
    for (final attempt in attempts) {
      if (attempt.run == null) continue;
      if (best == null || _score(attempt) > _score(best)) best = attempt;
    }
    return best;
  }

  static double _score(Attempt attempt) =>
      rank(attempt.run!) - (attempt.quality.hidesErrors ? 5 : 0);

  /// Orders runs by outcome: passing beats failing beats not compiling; ties
  /// go to the pass rate, then line coverage.
  static double rank(TestRun run) =>
      (run.allPassed ? 4 : 0) +
      (run.compiled ? 2 : 0) +
      run.passRate +
      (run.screenCoverage?.ratio ?? 0) * 0.5;

  TestRun? get finalRun => best?.run;

  bool get honestlyPassed => best?.honestlyPassed ?? false;

  /// Number of reflection repairs that were made.
  int get repairs => attempts.isEmpty ? 0 : attempts.length - 1;

  int get promptTokens =>
      attempts.fold(0, (sum, a) => sum + (a.generation.promptTokens ?? 0));
  int get outputTokens =>
      attempts.fold(0, (sum, a) => sum + (a.generation.outputTokens ?? 0));
  int get llmLatencyMs => attempts.fold(0, (sum, a) => sum + a.generation.latencyMs);
}
