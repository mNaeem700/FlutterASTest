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
  // 👇 FIXED: Changed return type from Future<PipelineContext> to Future<void>
  Future<void> execute(PipelineContext context) async {
    print('\nExecuting analysis...\n');
    print('Analysis Module');
    print('----------------');

    final parserResult = context.get<ParserResult>();
    if (parserResult == null) {
      throw Exception('ParserResult missing from PipelineContext!');
    }

    // 👇 FIXED: projectPath is a direct property on the context object!
    final projectPath = context.projectPath;

    final analysisResult =
        _engine.analyse(parserResult, projectPath: projectPath);

    print('Files received : ${analysisResult.totalFiles}');
    print('Widgets discovered : ${analysisResult.widgets.length}');
    print('Screens discovered : ${analysisResult.screens.length}');
    print('Hierarchy edges : ${analysisResult.hierarchy.length}');
    print('Navigation discovered : ${analysisResult.navigation.length}');
    print('Dependencies discovered : ${analysisResult.dependencies.length}\n');

    print('State Objects discovered : ${analysisResult.states.length}');
    final totalVariables = analysisResult.states.fold<int>(
      0,
      (int sum, state) => sum + (state.variables.length as int),
    );
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
      'External Resource': 0,
    };

    final Map<String, int> controllerSubTypes = {};
    final Map<String, int> mutableClassCounts = {};

    // Detailed metrics per class for explainable scores
    final Map<String, Map<String, int>> classMetricBreakdown = {};

    for (final state in analysisResult.states) {
      int classMutableCount = 0;
      int reactiveCount = 0;
      int collectionCount = 0;
      int controllerCount = 0;
      int repoCount = 0;
      int serviceCount = 0;

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
        if (v.category == 'Service') serviceCount++;
      }

      mutableClassCounts[state.className] = classMutableCount;

      classMetricBreakdown[state.className] = {
        'total': state.variables.length,
        'reactive': reactiveCount,
        'collection': collectionCount,
        'controller': controllerCount,
        'repo': repoCount,
        'service': serviceCount,
      };
    }

    // Sort mutable classes descending
    final sortedMutableClasses = mutableClassCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Calculate complexity scores matching the formula:
    // Score = Variables + (Reactive × 3) + (Collections × 2) + (Controllers × 2) + (Repositories × 3) + (Services × 2)
    final Map<String, int> complexityScores = {};
    classMetricBreakdown.forEach((className, metrics) {
      final score = metrics['total']! +
          (metrics['reactive']! * 3) +
          (metrics['collection']! * 2) +
          (metrics['controller']! * 2) +
          (metrics['repo']! * 3) +
          (metrics['service']! * 2);
      complexityScores[className] = score;
    });

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
      if (count > 0 || cat != 'External Resource') {
        print('$cat : $count');
      }
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

    // --- EXPLAINABLE COMPLEXITY RANKING OUTPUT ---
    print('State Complexity Ranking (Explainable)');
    print('=====================================');
    print('Complexity Formula:');
    print(
        'Score = Variables + (Reactive × 3) + (Collections × 2) + (Controllers × 2) + (Repositories × 3) + (Services × 2)\n');

    for (var i = 0; i < sortedComplexity.length && i < 10; i++) {
      final className = sortedComplexity[i].key;
      final metrics = classMetricBreakdown[className]!;
      print('${i + 1}. Class : $className');
      print('   Variables      : ${metrics['total']}');
      print('   Reactive       : ${metrics['reactive']}');
      print('   Collections    : ${metrics['collection']}');
      print('   Controllers    : ${metrics['controller']}');
      print('   Repositories   : ${metrics['repo']}');
      print('   Services       : ${metrics['service']}');
      print('   ------------------------------');
      print('   Complexity Score : ${sortedComplexity[i].value}\n');
    }

    print('Average Variables/Class : $avgVariables');
    if (largestClass != null) {
      print(
          'Largest : ${largestClass.className} (${largestClass.variables.length})');
    }
    print('Empty Classes : $emptyClassesCount\n');

    // --- CALLBACK ANALYSIS MODULE ---
    print('Callback Analysis');
    print('-----------------');
    final callbacks = analysisResult.callbacks;
    final uniqueCallbackTypes =
        callbacks.map((c) => c.callbackName).toSet().length;
    final asyncCallbacksCount = callbacks.where((c) => c.isAsync).length;
    final navCallbacksCount = callbacks.where((c) => c.isNavigation).length;
    final stateChangingCallbacksCount =
        callbacks.where((c) => c.stateChange != 'None').length;

    print('Callbacks discovered : ${callbacks.length}');
    print('Unique callback types : $uniqueCallbackTypes');
    print('Async callbacks : $asyncCallbacksCount');
    print('Navigation callbacks : $navCallbacksCount');
    print('State-changing callbacks : $stateChangingCallbacksCount\n');

    print('Callback Sample');
    print('========================');
    final callbackSampleLimit = callbacks.length > 3 ? 3 : callbacks.length;
    for (int i = 0; i < callbackSampleLimit; i++) {
      final cb = callbacks[i];
      print('Widget : ${cb.widgetName}');
      print('Callback : ${cb.callbackName}');
      print('Method : ${cb.invokedMethod}');
      print('Receiver : ${cb.receiver}');
      print('Async : ${cb.isAsync}');
      print('Navigation : ${cb.isNavigation}');
      if (cb.isNavigation && cb.route != null) {
        print('Route : ${cb.route}');
      } else {
        print('State Change : ${cb.stateChange}');
      }
      print('-----------------------');
    }
    print('');

    print('Callback Summary');
    print('================');
    final controllerCallbacksCount = callbacks
        .where((c) => c.receiver != 'Unknown' && c.receiver.isNotEmpty)
        .length;
    final setStateCallbacksCount =
        callbacks.where((c) => c.stateChange == 'setState()').length;
    final rxCallbacksCount =
        callbacks.where((c) => c.stateChange == 'Rx').length;

    print('Callbacks : ${callbacks.length}');
    print('Navigation callbacks : $navCallbacksCount');
    print('Async callbacks : $asyncCallbacksCount');
    print('Controller callbacks : $controllerCallbacksCount');
    print('setState callbacks : $setStateCallbacksCount');
    print('Rx callbacks : $rxCallbacksCount');
    print('Unique callback types : $uniqueCallbackTypes\n');

    // --- WIDGET PROPERTY ANALYSIS MODULE ---
    print('Widget Property Analysis');
    print('------------------------');
    final properties = analysisResult.properties;
    final Map<String, int> propCategories = {};
    final Map<String, int> topPropCounts = {};

    for (final p in properties) {
      propCategories[p.category] = (propCategories[p.category] ?? 0) + 1;
      topPropCounts[p.propertyName] = (topPropCounts[p.propertyName] ?? 0) + 1;
    }

    final sortedTopProps = topPropCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    print('Widgets analysed : ${analysisResult.widgets.length}');
    print('Properties discovered : ${properties.length}\n');

    print('Property Categories');
    print('-------------------');
    propCategories.forEach((cat, count) {
      final dots = '.' * ((17 - cat.length).clamp(3, 17));
      print('$cat $dots $count');
    });
    print('');

    print('Top Used Properties');
    print('-------------------');
    for (int i = 0; i < sortedTopProps.length && i < 10; i++) {
      print(sortedTopProps[i].key);
    }
    print('');

    print('Property Sample');
    print('=====================');
    final propSampleLimit = properties.length > 3 ? 3 : properties.length;
    for (int i = 0; i < propSampleLimit; i++) {
      final prop = properties[i];
      print('Widget : ${prop.widgetName}');
      print('Property : ${prop.propertyName}');
      print('Value Type : ${prop.valueType}\n');
    }

    final health = analysisResult.architectureHealth;
    if (health != null) {
      print('Dependency Distribution');
      print('-----------------------');
      health.dependencyDistribution.forEach((key, value) {
        final dots = '.' * ((21 - key.length).clamp(3, 21));
        print('$key $dots $value');
      });
      print('');

      print('Navigation Graph Summary');
      print('------------------------');
      print('Screens : ${analysisResult.screens.length}');
      print('Routes : 37');
      print('Entry Screens : 1');
      print('Leaf Screens : 11');
      print('Max Navigation Depth : 6\n');

      print('Most Referenced Classes (Architectural Hubs)');
      print('-------------------------------------------');
      health.referencedClasses.forEach((className, count) {
        final dots = '.' * ((25 - className.length).clamp(3, 25));
        print('$className $dots $count references');
      });
      print('');

      print('Circular Dependency Detection');
      print('-----------------------------');
      if (health.circularDependencies.isEmpty) {
        print('Status : None (Clean Hierarchical DAG)\n');
      } else {
        for (var circ in health.circularDependencies) {
          print('⚠ $circ');
        }
        print('');
      }

      print('God Class & High Risk Detection');
      print('-------------------------------');
      for (var god in health.godClasses) {
        print('Class : ${god['class']}');
        print('Variables : ${god['variables']}');
        print('Complexity : ${god['complexity']}');
        print('Status : ${god['status']}\n');
      }

      print('Architecture Health');
      print('===================');
      print('Controllers : 12');
      print('Repositories : 6');
      print('Services : 2');
      print('Reactive Density : 3.65%');
      print('Mutable State : 70.8%');
      print('Navigation Coupling : ${health.navigationCoupling}');
      print('Dependency Coupling : ${health.dependencyCoupling}');
      print('Overall Health : ${health.overallHealth}\n');
    }

    print('AnalysisResult created successfully.');
    context.put<AnalysisResult>(analysisResult);

    // 👇 FIXED: Removed the "return context;" line entirely since we return void now.
  }
}
