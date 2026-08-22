import 'dart:io';
import 'models/test_result.dart';

class TestExecutorService {
  Future<TestResult> runTest(File testFile, String screenName) async {
    final stopwatch = Stopwatch()..start();

    // Run the 'flutter test' command with coverage enabled
    final result = await Process.run(
      'flutter',
      ['test', testFile.path, '--coverage'],
      runInShell: true,
    );

    stopwatch.stop();

    final output = '${result.stdout}\n${result.stderr}';
    bool compilationSuccess = true;
    int passedCases = 0;
    int failedCases = 0;

    // 1. Check for compilation errors
    if (output.contains('Compilation failed') ||
        output.contains('Error: ') ||
        output.contains('Exception: ')) {
      if (result.exitCode != 0 && !output.contains('Some tests failed')) {
        compilationSuccess = false;
      }
    }

    // 2. Extract passed/failed metrics from Flutter CLI output
    final passedMatch = RegExp(r'\+(\d+)').firstMatch(output);
    if (passedMatch != null) {
      passedCases = int.tryParse(passedMatch.group(1)!) ?? 0;
    }

    final failedMatch = RegExp(r'\-(\d+)').firstMatch(output);
    if (failedMatch != null) {
      failedCases = int.tryParse(failedMatch.group(1)!) ?? 0;
    }

    // Fallbacks if Regex misses but tests succeeded/failed
    if (result.exitCode == 0 &&
        passedCases == 0 &&
        failedCases == 0 &&
        compilationSuccess) {
      passedCases = 1;
    } else if (result.exitCode != 0 &&
        passedCases == 0 &&
        failedCases == 0 &&
        compilationSuccess) {
      failedCases = 1;
    }

    return TestResult(
      screenName: screenName,
      compilationSuccess: compilationSuccess,
      passedCases: passedCases,
      failedCases: failedCases,
      output: output,
      executionTimeMs: stopwatch.elapsedMilliseconds,
    );
  }
}
