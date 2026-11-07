import '../execution/models/test_run.dart';
import '../experiment/models/screen_outcome.dart';

/// Execution metrics of a set of runs (one per screen).
class StateMetrics {
  const StateMetrics({
    required this.screens,
    required this.compiled,
    required this.allPassed,
    required this.passedCases,
    required this.totalCases,
  });

  factory StateMetrics.of(List<TestRun?> runs) => StateMetrics(
        screens: runs.length,
        compiled: runs.where((r) => r?.compiled ?? false).length,
        allPassed: runs.where((r) => r?.allPassed ?? false).length,
        passedCases: runs.fold(0, (sum, r) => sum + (r?.passed ?? 0)),
        totalCases: runs.fold(0, (sum, r) => sum + (r == null ? 0 : r.passed + r.failed)),
      );

  final int screens;
  final int compiled;

  /// Screens whose test file compiled and every test passed.
  final int allPassed;
  final int passedCases;

  /// Passed plus failed cases; skipped cases are not counted.
  final int totalCases;

  double get compilationRate => screens == 0 ? 0 : compiled / screens;
  double get executionSuccessRate => screens == 0 ? 0 : allPassed / screens;
  double get casePassRate => totalCases == 0 ? 0 : passedCases / totalCases;

  Map<String, dynamic> toJson() => {
        'compiled': compiled,
        'compilationRate': _round(compilationRate),
        'allPassed': allPassed,
        'executionSuccessRate': _round(executionSuccessRate),
        'passedCases': passedCases,
        'totalCases': totalCases,
        'casePassRate': _round(casePassRate),
      };
}

/// Aggregate metrics of one experiment run, for RQ2–RQ4.
class RunMetrics {
  const RunMetrics({
    required this.screens,
    required this.generated,
    required this.initial,
    required this.finalState,
    required this.meanScreenCoverage,
    required this.mergedCoverage,
    required this.repairs,
    required this.promptTokens,
    required this.outputTokens,
    required this.llmLatencyMs,
    required this.testDurationMs,
    this.details = const {},
  });

  factory RunMetrics.compute(List<ScreenOutcome> outcomes, {required LineCoverage mergedCoverage}) {
    final finalRuns = [for (final o in outcomes) o.finalRun];
    // A screen whose test produced no coverage of its own file counts as 0%.
    final coverages = [for (final run in finalRuns) run?.screenCoverage?.ratio ?? 0.0];
    return RunMetrics(
      screens: outcomes.length,
      generated: outcomes
          .where((o) => o.attempts.isNotEmpty && o.attempts.first.generation.succeeded)
          .length,
      initial: StateMetrics.of(
          [for (final o in outcomes) o.attempts.isEmpty ? null : o.attempts.first.run]),
      finalState: StateMetrics.of(finalRuns),
      meanScreenCoverage:
          coverages.isEmpty ? 0 : coverages.reduce((a, b) => a + b) / coverages.length,
      mergedCoverage: mergedCoverage,
      repairs: outcomes.fold(0, (sum, o) => sum + o.repairs),
      promptTokens: outcomes.fold(0, (sum, o) => sum + o.promptTokens),
      outputTokens: outcomes.fold(0, (sum, o) => sum + o.outputTokens),
      llmLatencyMs: outcomes.fold(0, (sum, o) => sum + o.llmLatencyMs),
      details: _details(outcomes, finalRuns),
      testDurationMs: outcomes.fold(
          0,
          (sum, o) =>
              sum + o.attempts.fold<int>(0, (s, a) => s + (a.run?.durationMs ?? 0))),
    );
  }

  /// Mean of the [ratio] of each screen, counting missing data as 0.
  static double _mean(Iterable<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  static Map<String, dynamic> _details(List<ScreenOutcome> outcomes, List<TestRun?> runs) {
    // A screen with no navigation or state changes has nothing to cover in
    // that dimension, so it is left out of that mean rather than counted as 0.
    double structural(Ratio Function(StructuralCoverage s) pick) => _round(_mean([
          for (final run in runs)
            if (run?.structural != null && pick(run!.structural!).found > 0)
              pick(run.structural!).value,
        ]));
    final qualities = [for (final o in outcomes) if (o.best != null) o.best!.quality];
    final smells = <String, int>{};
    for (final quality in qualities) {
      quality.smells.forEach((k, v) => smells[k] = (smells[k] ?? 0) + v);
    }
    final failures = <String, int>{};
    for (final outcome in outcomes) {
      outcome.attempts.first.analysis?.categories.forEach((k, v) {
        failures[k.name] = (failures[k.name] ?? 0) + v;
      });
    }
    final stops = <String, int>{};
    for (final outcome in outcomes) {
      final reason = outcome.stoppingReason;
      if (reason != null) stops[reason] = (stops[reason] ?? 0) + 1;
    }
    return {
      'meanBranchCoverage': _round(_mean(runs.map((r) => r?.branchCoverage.value ?? 0))),
      'meanFunctionCoverage': _round(_mean(runs.map((r) => r?.functionCoverage.value ?? 0))),
      'meanWidgetCoverage': structural((s) => s.widgets),
      'meanInteractionCoverage': structural((s) => s.interactions),
      'meanNavigationCoverage': structural((s) => s.navigation),
      'meanStateCoverage': structural((s) => s.state),
      'flakyTests': runs.fold<int>(0, (sum, r) => sum + (r?.flakyTests.length ?? 0)),
      'rejectedBeforeExecution': runs.where((r) => r?.rejectedBeforeExecution ?? false).length,
      'meanAssertionsPerTest': _round(_mean(qualities.map((q) => q.assertionsPerTest))),
      'testSmells': smells,
      'initialFailureCategories': failures,
      'stoppingReasons': stops,
    };
  }

  /// Coverage, quality and reflection aggregates.
  final Map<String, dynamic> details;

  final int screens;
  final int generated;

  /// After iteration 0, before any reflection repair.
  final StateMetrics initial;

  /// After the last attempt of every screen.
  final StateMetrics finalState;

  /// Mean line coverage of each screen's own source file.
  final double meanScreenCoverage;

  /// Union of all final runs' coverage over the project files they loaded.
  final LineCoverage mergedCoverage;
  final int repairs;
  final int promptTokens;
  final int outputTokens;
  final int llmLatencyMs;
  final int testDurationMs;

  Map<String, dynamic> toJson() => {
        'screens': screens,
        'generated': generated,
        'initial': initial.toJson(),
        'final': finalState.toJson(),
        'meanScreenCoverage': _round(meanScreenCoverage),
        'mergedCoverageOfLoadedFiles': mergedCoverage.toJson(),
        'repairs': repairs,
        'promptTokens': promptTokens,
        'outputTokens': outputTokens,
        'llmLatencyMs': llmLatencyMs,
        'testDurationMs': testDurationMs,
        ...details,
      };
}

double _round(double value) => double.parse(value.toStringAsFixed(4));
