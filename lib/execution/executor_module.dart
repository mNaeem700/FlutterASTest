import 'dart:io';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import 'test_executor_service.dart';
import 'models/test_result.dart';

class ExecutorModule implements PipelineModule {
  final TestExecutorService _executorService;

  ExecutorModule({TestExecutorService? executorService})
      : _executorService = executorService ?? TestExecutorService();

  @override
  PipelineStage get stage => PipelineStage.analysis;

  @override
  Future<void> execute(PipelineContext context) async {
    print('\nExecuting Generated Tests (Step 10)...');
    print('--------------------------------------');

    final testDir = Directory('generated_tests');
    if (!await testDir.exists()) {
      throw Exception(
          'No generated_tests directory found. Run the LLM module first.');
    }

    final testFiles = testDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .toList();

    if (testFiles.isEmpty) {
      print('No test files found to execute.');
      return;
    }

    final List<TestResult> results = [];
    int totalExecutionTime = 0;

    // Run tests individually and log status
    for (final file in testFiles) {
      final fileName = file.uri.pathSegments.last;
      final screenName = fileName.replaceAll('_test.dart', '');

      final result = await _executorService.runTest(file, screenName);
      results.add(result);
      totalExecutionTime += result.executionTimeMs;

      print('\n$fileName');
      print('Compile : ${result.compilationSuccess ? "Success" : "Failed"}');
      print('Passed  : ${result.passedCases}');
      print('Failed  : ${result.failedCases}');
      print(
          'Time    : ${(result.executionTimeMs / 1000).toStringAsFixed(1)} s');
    }

    // --- STEP 11: BUILD EVALUATION REPORT ---
    final totalScreens = testFiles.length;
    int compileSuccess = results.where((r) => r.compilationSuccess).length;
    int compileFailed = results.length - compileSuccess;

    int totalPassed = results.fold(0, (sum, r) => sum + r.passedCases);
    int totalFailed = results.fold(0, (sum, r) => sum + r.failedCases);
    int totalCases = totalPassed + totalFailed;

    double passRate = totalCases > 0 ? (totalPassed / totalCases) * 100 : 0.0;
    double avgTime = (totalExecutionTime / results.length) / 1000;

    print('\nEvaluation Summary');
    print('==================');
    print('Screens               : $totalScreens');
    print('Generated Tests       : $totalScreens');
    print('Compilation Success   : $compileSuccess');
    print('Compilation Failed    : $compileFailed');
    print('');
    print('Total Test Cases      : $totalCases');
    print('Passed                : $totalPassed');
    print('Failed                : $totalFailed');
    print('Pass Rate             : ${passRate.toStringAsFixed(1)}%');
    print('');
    print('Average Execution Time: ${avgTime.toStringAsFixed(1)} sec\n');

    context.put<List<TestResult>>(results);

    // --- GENERATE HTML COVERAGE REPORT ---
    print('Generating Coverage Report...');
    final lcovFile = File('coverage/lcov.info');

    if (await lcovFile.exists()) {
      final genResult = await Process.run(
          'genhtml', ['coverage/lcov.info', '-o', 'coverage/html'],
          runInShell: true);
      if (genResult.exitCode == 0) {
        print('Coverage report saved to coverage/html/index.html');
      } else {
        print(
            'Failed to generate HTML coverage (Make sure lcov/genhtml is installed on your OS).');
      }
    } else {
      print(
          'Coverage file not found. Ensure the target project supports coverage generation.');
    }
  }
}
