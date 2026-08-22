class TestResult {
  final String screenName;
  final bool compilationSuccess;
  final int passedCases;
  final int failedCases;
  final String output;
  final int executionTimeMs;

  TestResult({
    required this.screenName,
    required this.compilationSuccess,
    required this.passedCases,
    required this.failedCases,
    required this.output,
    required this.executionTimeMs,
  });

  int get totalCases => passedCases + failedCases;
}
