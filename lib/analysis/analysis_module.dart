import 'package:flutterastest/orchestrator/pipeline_context.dart';
import 'package:flutterastest/orchestrator/pipeline_stage.dart';
import 'package:flutterastest/parser/models/parser_result.dart';
import 'package:flutterastest/analysis/analysis_result.dart';
import 'package:flutterastest/orchestrator/contracts/pipeline_module.dart';
import 'analysis_engine.dart';

class AnalysisModule implements PipelineModule {
  final AnalysisEngine _engine;

  const AnalysisModule({AnalysisEngine engine = const AnalysisEngine()})
      : _engine = engine;

  @override
  get stage => PipelineStage.analysis;

  @override
  Future<PipelineContext> execute(PipelineContext context) async {
    print('\nExecuting analysis...\n');
    print('Analysis Module');
    print('----------------');

    final parserResult = context.get<ParserResult>();
    if (parserResult == null) {
      throw Exception('ParserResult missing from PipelineContext!');
    }

    final analysisResult = _engine.analyse(parserResult);

    print('Files received : ${analysisResult.totalFiles}');
    print('Widgets discovered : ${analysisResult.widgets.length}');
    print('Screens discovered : ${analysisResult.screens.length}');
    print('Hierarchy edges : ${analysisResult.hierarchy.length}');
    print('Navigation discovered : ${analysisResult.navigation.length}');
    print('Dependencies discovered : ${analysisResult.dependencies.length}\n');

    print('State Objects discovered : ${analysisResult.states.length}');
    final totalVariables = analysisResult.states
        .fold<int>(0, (sum, state) => sum + state.variables.length);
    print('State Variables : $totalVariables\n');

    final sortedStates = List.from(analysisResult.states)
      ..sort((a, b) => a.className.compareTo(b.className));

    final descendingStates = List.from(analysisResult.states)
      ..sort((a, b) => b.variables.length.compareTo(a.variables.length));

    print('Variables per Class (Descending)\n--------------------------------');
    for (final state in descendingStates) {
      final dots = '.' * ((35 - state.className.length).toInt().clamp(0, 35));
      print('${state.className} $dots ${state.variables.length}');
    }
    print('');

    print('State Sample\n=====================');
    int sampleCount = 0;
    for (final state in sortedStates) {
      if (state.variables.isEmpty) continue;

      print('Class : ${state.className}');
      print('Variables : ${state.variables.length}');
      print('------------------------------');
      for (final v in state.variables) {
        print(v.name);
        print('Type : ${v.type}');
        print('Category : ${v.category}');
        print('Final : ${v.isFinal}');
        print('Late : ${v.isLate}');
        print('Nullable : ${v.isNullable}');
        print('Static : ${v.isStatic}');
        print('');
      }
      print('------------------------------');

      sampleCount++;
      if (sampleCount >= 3) break;
    }

    // --- ENHANCED RESEARCH STATISTICS & METRICS ---
    int mutableCount = 0;
    int finalCount = 0;

    final Map<String, int> categoryCounts = {
      'Primitive': 0,
      'Reactive': 0,
      'Repository': 0,
      'Service': 0,
      'Collection': 0,
      'UI Controller': 0,
      'Model': 0,
    };

    final Map<String, int> controllerSubTypes = {};
    final Map<String, int> mutableClassCounts = {};
    final Map<String, int> complexityScores = {};

    for (final state in analysisResult.states) {
      int classMutableCount = 0;
      int reactiveCount = 0;
      int collectionCount = 0;
      int controllerCount = 0;
      int repoCount = 0;

      for (final v in state.variables) {
        if (v.isFinal) {
          finalCount++;
        } else {
          mutableCount++;
          classMutableCount++;
        }

        // Category breakdown
        if (categoryCounts.containsKey(v.category)) {
          categoryCounts[v.category] = categoryCounts[v.category]! + 1;
        }

        // Sub-metrics for Complexity Score & Controllers
        if (v.category == 'Reactive') reactiveCount++;
        if (v.category == 'Collection') collectionCount++;
        if (v.category == 'UI Controller') {
          controllerCount++;
          controllerSubTypes[v.type] = (controllerSubTypes[v.type] ?? 0) + 1;
        }
        if (v.category == 'Repository') repoCount++;
      }

      mutableClassCounts[state.className] = classMutableCount;

      // Complexity Score Formula: variables + (reactive * 2) + (collections * 2) + (controllers * 3) + (repositories * 2)
      final score = state.variables.length +
          (reactiveCount * 2) +
          (collectionCount * 2) +
          (controllerCount * 3) +
          (repoCount * 2);
      complexityScores[state.className] = score;
    }

    // Sort mutable classes descending
    final sortedMutableClasses = mutableClassCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Sort complexity ranking descending
    final sortedComplexity = complexityScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final emptyClassesCount =
        analysisResult.states.where((s) => s.variables.isEmpty).length;
    final avgVariables = analysisResult.states.isNotEmpty
        ? (totalVariables / analysisResult.states.length).toStringAsFixed(2)
        : '0.00';
    final largestClass =
        descendingStates.isNotEmpty ? descendingStates.first : null;

    final finalPercentage = totalVariables > 0
        ? ((finalCount / totalVariables) * 100).toStringAsFixed(1)
        : '0.0';
    final mutablePercentage = totalVariables > 0
        ? ((mutableCount / totalVariables) * 100).toStringAsFixed(1)
        : '0.0';
    final rxPercentage = totalVariables > 0
        ? ((categoryCounts['Reactive']! / totalVariables) * 100)
            .toStringAsFixed(2)
        : '0.0';

    // --- PRINT DETAILED RESEARCH SUMMARY ---
    print('State Summary\n================');
    print('Classes : ${analysisResult.states.length}');
    print('Variables : $totalVariables\n');

    print('Immutable : $finalCount ($finalPercentage%)');
    print('Mutable : $mutableCount ($mutablePercentage%)\n');

    print('Category Distribution');
    categoryCounts.forEach((cat, count) {
      print('$cat : $count');
    });
    print('');

    print(
        'Reactive Variables : ${categoryCounts['Reactive']} / $totalVariables ($rxPercentage%)\n');

    print('Controller Type Breakdown');
    controllerSubTypes.forEach((type, count) {
      print('$type : $count');
    });
    print('');

    print('Most Mutable Classes');
    for (var i = 0; i < sortedMutableClasses.length && i < 3; i++) {
      print(
          '${sortedMutableClasses[i].key}\nMutable : ${sortedMutableClasses[i].value}\n');
    }

    print('State Complexity Ranking (Top 10)');
    for (var i = 0; i < sortedComplexity.length && i < 10; i++) {
      print(
          '${i + 1}. ${sortedComplexity[i].key} (Score: ${sortedComplexity[i].value})');
    }
    print('');

    print('Average Variables/Class : $avgVariables');
    if (largestClass != null) {
      print(
          'Largest : ${largestClass.className} (${largestClass.variables.length})');
    }
    print('Empty Classes : $emptyClassesCount\n');

    print('AnalysisResult created successfully.');

    context.put<AnalysisResult>(analysisResult);
    return context;
  }
}
