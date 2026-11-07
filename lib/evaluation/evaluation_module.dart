import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../analysis/analysis_result.dart';
import '../execution/lcov.dart';
import '../execution/models/test_run.dart';
import '../execution/test_installer.dart';
import '../experiment/experiment_config.dart';
import '../experiment/models/screen_outcome.dart';
import '../experiment/run_artifacts.dart';
import '../llm/llm_service.dart';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import '../prompt_optimizer/prompt_builder.dart';
import 'pdf_report.dart';
import 'run_metrics.dart';

/// Computes the run's metrics and exports them to `results.json` (complete,
/// including every attempt) and `results.csv` (one row per screen).
class EvaluationModule implements PipelineModule {
  const EvaluationModule({required this.llmService});

  final LlmService llmService;

  @override
  PipelineStage get stage => PipelineStage.evaluation;

  @override
  Future<void> execute(PipelineContext context) async {
    final config = context.get<ExperimentConfig>() ?? const ExperimentConfig();
    final outcomes = context.get<List<ScreenOutcome>>();
    final analysis = context.get<AnalysisResult>();
    if (outcomes == null || analysis == null) {
      throw Exception('ScreenOutcomes or AnalysisResult missing from PipelineContext!');
    }

    final reports = <LcovReport>[];
    for (final outcome in outcomes) {
      final path = outcome.finalRun?.lcovPath;
      if (path != null && File(path).existsSync()) {
        reports.add(LcovReport.parse(File(path).readAsStringSync(),
            projectPath: context.projectPath));
      }
    }
    final metrics =
        RunMetrics.compute(outcomes, mergedCoverage: LcovReport.merge(reports).total);

    final installed = config.installTests
        ? const TestInstaller().install(context.projectPath, outcomes, unit: config.kind == TestKind.unit)
        : const <String>[];

    if (installed.isNotEmpty) {
      try {
        await Process.run(
            'dart', ['format', p.join(context.projectPath, 'test', TestInstaller.directoryName)],
            runInShell: true);
      } on ProcessException {
        print('dart format is not available; installed tests are unformatted.');
      }
    }

    final artifacts = RunArtifacts(config);
    final json = {
      'meta': {
        'tool': 'FlutterASTest',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'projectPath': context.projectPath,
        'packageName': analysis.projectInfo.packageName,
        'stateManagement': analysis.projectInfo.stateManagement,
        'model': llmService.model,
        'promptTemplateVersion': PromptBuilder.templateVersion,
        ...config.toJson(),
      },
      'summary': metrics.toJson(),
      'installedTests': installed,
      'screens': [for (final outcome in outcomes) _screenJson(outcome)],
    };
    await File(artifacts.resultsJson)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    await File(artifacts.resultsCsv).writeAsString(toCsv(outcomes));
    await File(artifacts.reportHtml).writeAsString(toHtml(config.runName, outcomes));
    await File(artifacts.reportPdf).writeAsBytes(const PdfReport().build(
      'FlutterASTest: ${config.runName}',
      [
        'Project: ${analysis.projectInfo.packageName}',
        'Model: ${llmService.model}',
        'Screens: ${metrics.screens}  Compiled: ${metrics.finalState.compiled}  '
            'All tests pass: ${metrics.finalState.allPassed}',
        'Test cases passed: ${metrics.finalState.passedCases} / ${metrics.finalState.totalCases}',
        'Mean line coverage: ${(metrics.meanScreenCoverage * 100).toStringAsFixed(1)}%',
        'Tokens prompt / output: ${metrics.promptTokens} / ${metrics.outputTokens}',
        '',
        'Screen                           Status   Tests   Line%  Branch%',
        for (final outcome in outcomes)
          '${outcome.screenName.padRight(33)}'
              '${(outcome.finalRun?.allPassed ?? false ? 'pass' : 'fail').padRight(9)}'
              '${'${outcome.finalRun?.passed ?? 0}/${(outcome.finalRun?.passed ?? 0) + (outcome.finalRun?.failed ?? 0)}'.padRight(8)}'
              '${((outcome.finalRun?.screenCoverage?.ratio ?? 0) * 100).toStringAsFixed(1).padRight(7)}'
              '${((outcome.finalRun?.branchCoverage.value ?? 0) * 100).toStringAsFixed(1)}',
      ],
    ));

    if (config.installTests) {
      print(friendlySummary(outcomes, installed, artifacts.root));
    } else {
      _print(config, metrics);
      print('Results: ${artifacts.resultsJson}');
      print('         ${artifacts.resultsCsv}\n');
    }
  }

  Map<String, dynamic> _screenJson(ScreenOutcome outcome) => {
        'screen': outcome.screenName,
        'screenFile': outcome.screenFile,
        'repairs': outcome.repairs,
        'bestIteration': outcome.best?.iteration,
        'honestlyPassed': outcome.honestlyPassed,
        'stoppingReason': outcome.stoppingReason,
        'promptTokens': outcome.promptTokens,
        'outputTokens': outcome.outputTokens,
        'llmLatencyMs': outcome.llmLatencyMs,
        'final': outcome.finalRun?.toJson(),
        'attempts': [for (final attempt in outcome.attempts) attempt.toJson()],
      };

  static const csvHeader = [
    'screen',
    'screen_file',
    'generated',
    'compiled',
    'timed_out',
    'tests',
    'passed',
    'failed',
    'all_passed',
    'screen_lines_found',
    'screen_lines_hit',
    'screen_coverage_pct',
    'initial_compiled',
    'initial_all_passed',
    'repairs',
    'prompt_tokens',
    'output_tokens',
    'llm_latency_ms',
    'test_duration_ms',
    'pass_rate_pct',
    'branch_coverage_pct',
    'widget_coverage_pct',
    'interaction_coverage_pct',
    'navigation_coverage_pct',
    'state_coverage_pct',
    'flaky_tests',
    'assertions_per_test',
    'test_smells',
    'stopping_reason',
    'maintainability_index',
    'mutation_score_pct',
    'hides_errors',
  ];

  static String toCsv(List<ScreenOutcome> outcomes) {
    final rows = <List<Object?>>[csvHeader];
    for (final outcome in outcomes) {
      final run = outcome.finalRun;
      final initial = outcome.attempts.isEmpty ? null : outcome.attempts.first.run;
      final coverage = run?.screenCoverage ?? LineCoverage.none;
      final quality = outcome.best?.quality;
      String pct(double ratio) => (ratio * 100).toStringAsFixed(2);
      // Empty when the screen has nothing of that kind to cover.
      String structural(Ratio? ratio) =>
          ratio == null || ratio.found == 0 ? '' : pct(ratio.value);
      rows.add([
        outcome.screenName,
        outcome.screenFile,
        outcome.attempts.isNotEmpty && outcome.attempts.first.generation.succeeded,
        run?.compiled ?? false,
        run?.timedOut ?? false,
        run?.cases.length ?? 0,
        run?.passed ?? 0,
        run?.failed ?? 0,
        run?.allPassed ?? false,
        coverage.linesFound,
        coverage.linesHit,
        (coverage.ratio * 100).toStringAsFixed(2),
        initial?.compiled ?? false,
        initial?.allPassed ?? false,
        outcome.repairs,
        outcome.promptTokens,
        outcome.outputTokens,
        outcome.llmLatencyMs,
        outcome.attempts.fold<int>(0, (sum, a) => sum + (a.run?.durationMs ?? 0)),
        pct(run?.passRate ?? 0),
        pct(run?.branchCoverage.value ?? 0),
        structural(run?.structural?.widgets),
        structural(run?.structural?.interactions),
        structural(run?.structural?.navigation),
        structural(run?.structural?.state),
        run?.flakyTests.length ?? 0,
        (quality?.assertionsPerTest ?? 0).toStringAsFixed(2),
        quality?.totalSmells ?? 0,
        outcome.stoppingReason ?? '',
        (quality?.maintainabilityIndex ?? 0).toStringAsFixed(2),
        outcome.best?.mutation == null ? '' : pct(outcome.best!.mutation!.score),
        quality?.hidesErrors ?? false,
      ]);
    }
    return '${rows.map((row) => row.map(_csvCell).join(',')).join('\n')}\n';
  }

  /// A summary to read in a browser; `results.json` remains the full record.
  static String toHtml(String runName, List<ScreenOutcome> outcomes) {
    String esc(String s) =>
        s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    String pct(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';
    final rows = StringBuffer();
    for (final outcome in outcomes) {
      final run = outcome.finalRun;
      final status = run == null
          ? 'not run'
          : run.allPassed
              ? 'passed'
              : run.compiled
                  ? 'failed'
                  : 'does not compile';
      rows.writeln('<tr><td>${esc(outcome.screenName)}</td><td>$status</td>'
          '<td>${run?.passed ?? 0} / ${(run?.passed ?? 0) + (run?.failed ?? 0)}</td>'
          '<td>${pct(run?.screenCoverage?.ratio ?? 0)}</td>'
          '<td>${pct(run?.branchCoverage.value ?? 0)}</td>'
          '<td>${outcome.repairs}</td></tr>');
    }
    return '<!doctype html><meta charset="utf-8"><title>${esc(runName)}</title>'
        '<style>body{font:14px sans-serif;margin:24px}table{border-collapse:collapse}'
        'td,th{border:1px solid #bbb;padding:6px 10px;text-align:left}</style>'
        '<h1>FlutterASTest: ${esc(runName)}</h1><table><tr><th>Screen</th><th>Status</th>'
        '<th>Tests passed</th><th>Line coverage</th><th>Branch coverage</th><th>Repairs</th></tr>'
        '$rows</table>';
  }

  /// What happened and what to do next, in words a developer can act on.
  static String friendlySummary(List<ScreenOutcome> outcomes, List<String> installed, String runRoot) {
    final passing = outcomes.where((o) => o.honestlyPassed).length;
    final tests =
        outcomes.fold<int>(0, (sum, o) => sum + (o.honestlyPassed ? o.finalRun!.passed : 0));
    final out = StringBuffer()
      ..writeln()
      ..writeln('Result: $passing of ${outcomes.length} have working tests ($tests tests).')
      ..writeln();
    for (final outcome in outcomes) {
      final run = outcome.finalRun;
      final analysis = outcome.best?.analysis;
      if (analysis?.isAppBug ?? false) {
        out
          ..writeln('[bug]  ${outcome.screenName}: possible bug in your app: ${run?.reason}')
          ..writeln('       ${analysis!.recommendations.first}');
      } else if ((run?.allPassed ?? false) && !outcome.honestlyPassed) {
        out.writeln('[weak] ${outcome.screenName}: its tests pass only by ignoring errors, so they were not added.');
      } else if (run?.allPassed ?? false) {
        final coverage = ((run!.screenCoverage?.ratio ?? 0) * 100).toStringAsFixed(0);
        out.writeln('[pass] ${outcome.screenName}: ${run.passed} tests, $coverage% line coverage');
      } else {
        out.writeln('[fail] ${outcome.screenName}: ${run?.reason ?? 'no test was generated'}');
        final advice = analysis?.recommendations;
        if (advice != null && advice.isNotEmpty) out.writeln('       What to try: ${advice.first}');
      }
    }
    out.writeln();
    if (installed.isNotEmpty) {
      out.writeln('Added to your project:');
      for (final path in installed) {
        out.writeln('  $path');
      }
    }
    if (passing < outcomes.length) {
      out
        ..writeln('Failed tests were not added, so your test suite stays green. You can read and fix them here:')
        ..writeln('  ${p.join(runRoot, 'tests')}');
    }
    out.write('Full report: ${p.join(runRoot, 'report.html')}');
    return out.toString();
  }

  static String _csvCell(Object? value) {
    final text = '$value';
    return text.contains(RegExp(r'[",\n]')) ? '"${text.replaceAll('"', '""')}"' : text;
  }

  static void _print(ExperimentConfig config, RunMetrics m) {
    String pct(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';
    final f = m.finalState;
    print('\nEvaluation summary (${config.runName})');
    print('==========================================');
    print('Screens                      : ${m.screens}');
    print('Generated by LLM             : ${m.generated}');
    if (config.reflect) {
      print('Compiled        initial/final: ${m.initial.compiled} / ${f.compiled}');
      print('All tests pass  initial/final: ${m.initial.allPassed} / ${f.allPassed}');
      print('Repairs made                 : ${m.repairs}');
    } else {
      print('Compiled                     : ${f.compiled} (${pct(f.compilationRate)})');
      print('All tests pass               : ${f.allPassed} (${pct(f.executionSuccessRate)})');
    }
    print('Test cases passed / total    : ${f.passedCases} / ${f.totalCases} '
        '(${pct(f.casePassRate)})');
    print('Mean screen line coverage    : ${pct(m.meanScreenCoverage)}');
    print('Merged coverage, loaded files: ${pct(m.mergedCoverage.ratio)} '
        '(${m.mergedCoverage.linesHit}/${m.mergedCoverage.linesFound} lines)');
    print('Branch / widget coverage     : ${pct(m.details['meanBranchCoverage'] as double)} / '
        '${pct(m.details['meanWidgetCoverage'] as double)}');
    print('Interaction / nav / state    : ${pct(m.details['meanInteractionCoverage'] as double)} / '
        '${pct(m.details['meanNavigationCoverage'] as double)} / '
        '${pct(m.details['meanStateCoverage'] as double)}');
    print('Assertions per test / flaky  : ${m.details['meanAssertionsPerTest']} / ${m.details['flakyTests']}');
    print('Maintainability index        : ${m.details['meanMaintainabilityIndex']}');
    final mutation = m.details['meanMutationScore'] as double?;
    if (mutation != null) print('Mean mutation score          : ${pct(mutation)}');
    print('Tokens prompt / output       : ${m.promptTokens} / ${m.outputTokens}');
    print('LLM time / test time         : ${(m.llmLatencyMs / 1000).toStringAsFixed(1)} s / '
        '${(m.testDurationMs / 1000).toStringAsFixed(1)} s');
  }
}
