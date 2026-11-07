import 'package:meta/meta.dart';

enum TestCaseStatus { passed, failed, skipped }

@immutable
class TestCaseResult {
  const TestCaseResult({required this.name, required this.status, this.message});

  final String name;
  final TestCaseStatus status;

  /// Failure message and stack trace start, for failed tests.
  final String? message;

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status.name,
        if (message != null) 'message': message,
      };
}

/// Line coverage of one source file.
@immutable
class LineCoverage {
  const LineCoverage({required this.linesFound, required this.linesHit});

  static const none = LineCoverage(linesFound: 0, linesHit: 0);

  final int linesFound;
  final int linesHit;

  double get ratio => linesFound == 0 ? 0 : linesHit / linesFound;

  Map<String, dynamic> toJson() => {
        'linesFound': linesFound,
        'linesHit': linesHit,
        'percent': double.parse((ratio * 100).toStringAsFixed(2)),
      };
}

/// Covered and total items of some kind.
@immutable
class Ratio {
  const Ratio(this.hit, this.found);

  final int hit;
  final int found;

  double get value => found == 0 ? 0 : hit / found;

  Map<String, dynamic> toJson() => {'hit': hit, 'found': found};
}

/// Coverage of what the screen does rather than of its lines (Doc 16.9).
@immutable
class StructuralCoverage {
  const StructuralCoverage({
    required this.widgets,
    required this.interactions,
    required this.navigation,
    required this.state,
    this.uncoveredInteractions = const [],
    this.uncoveredNavigation = const [],
    this.uncoveredState = const [],
  });

  final Ratio widgets;
  final Ratio interactions;
  final Ratio navigation;
  final Ratio state;
  final List<String> uncoveredInteractions;
  final List<String> uncoveredNavigation;
  final List<String> uncoveredState;

  Map<String, dynamic> toJson() => {
        'widgets': widgets.toJson(),
        'interactions': interactions.toJson(),
        'navigation': navigation.toJson(),
        'state': state.toJson(),
        'uncoveredInteractions': uncoveredInteractions,
        'uncoveredNavigation': uncoveredNavigation,
        'uncoveredState': uncoveredState,
      };
}

/// The result of running one generated test file with `flutter test`.
@immutable
class TestRun {
  const TestRun({
    required this.compiled,
    required this.cases,
    required this.durationMs,
    this.loadErrors = const [],
    this.timedOut = false,
    this.screenCoverage,
    this.lcovPath,
    this.branchCoverage = const Ratio(0, 0),
    this.functionCoverage = const Ratio(0, 0),
    this.structural,
    this.flakyTests = const [],
    this.rejectedBeforeExecution = false,
  });

  /// False when the file failed to compile or load.
  final bool compiled;
  final List<TestCaseResult> cases;
  final int durationMs;

  /// Compilation or loading errors reported by `flutter test`.
  final List<String> loadErrors;
  final bool timedOut;

  /// Line coverage of the screen's own source file; null when no coverage
  /// was recorded for it (e.g. the test did not compile).
  final LineCoverage? screenCoverage;
  final String? lcovPath;
  final Ratio branchCoverage;
  final Ratio functionCoverage;
  final StructuralCoverage? structural;

  /// Tests whose outcome changed between reruns. They stay counted as failed.
  final List<String> flakyTests;

  /// The response validator stopped the file before `flutter test`.
  final bool rejectedBeforeExecution;

  int get passed => cases.where((c) => c.status == TestCaseStatus.passed).length;
  int get failed => cases.where((c) => c.status == TestCaseStatus.failed).length;
  int get skipped => cases.where((c) => c.status == TestCaseStatus.skipped).length;

  /// The file compiled, contains at least one test, and every test passed.
  bool get allPassed => compiled && !timedOut && passed > 0 && failed == 0;

  double get passRate => passed + failed == 0 ? 0 : passed / (passed + failed);

  TestRun copyWith({
    LineCoverage? screenCoverage,
    Ratio? branchCoverage,
    Ratio? functionCoverage,
    StructuralCoverage? structural,
    List<String>? flakyTests,
    int? durationMs,
  }) =>
      TestRun(
        compiled: compiled,
        cases: cases,
        durationMs: durationMs ?? this.durationMs,
        loadErrors: loadErrors,
        timedOut: timedOut,
        screenCoverage: screenCoverage ?? this.screenCoverage,
        lcovPath: lcovPath,
        branchCoverage: branchCoverage ?? this.branchCoverage,
        functionCoverage: functionCoverage ?? this.functionCoverage,
        structural: structural ?? this.structural,
        flakyTests: flakyTests ?? this.flakyTests,
        rejectedBeforeExecution: rejectedBeforeExecution,
      );

  Map<String, dynamic> toJson() => {
        'compiled': compiled,
        'timedOut': timedOut,
        'rejectedBeforeExecution': rejectedBeforeExecution,
        'passed': passed,
        'failed': failed,
        'skipped': skipped,
        'durationMs': durationMs,
        'screenCoverage': screenCoverage?.toJson(),
        'branchCoverage': branchCoverage.toJson(),
        'functionCoverage': functionCoverage.toJson(),
        'structuralCoverage': structural?.toJson(),
        if (flakyTests.isNotEmpty) 'flakyTests': flakyTests,
        if (loadErrors.isNotEmpty) 'loadErrors': loadErrors,
        'cases': [for (final c in cases) c.toJson()],
      };
}
