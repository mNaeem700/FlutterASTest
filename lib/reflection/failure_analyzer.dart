import '../execution/models/test_run.dart';

enum FailureCategory {
  rejected,
  undefinedSymbol,
  missingImport,
  compilation,
  timeout,
  noTests,
  finderNotFound,
  pumpAndSettleTimeout,
  missingDependency,
  layoutOverflow,
  assertion,
  runtimeException,
}

/// Diagnosis of one run (Doc 15.9): failure categories, primary root cause
/// and evidence-based recommendations. Rules are deterministic, so the same
/// run always yields the same diagnosis.
class FailureAnalysis {
  const FailureAnalysis({
    required this.categories,
    required this.primaryCause,
    required this.recommendations,
    required this.signature,
    this.secondaryCauses = const [],
    this.evidence = const [],
    this.confidence = 0,
  });

  final Map<FailureCategory, int> categories;
  final String primaryCause;
  final List<String> recommendations;

  /// Identifies the failure; the same signature twice means no progress.
  final String signature;

  final List<String> secondaryCauses;

  /// First lines of the errors the diagnosis rests on.
  final List<String> evidence;

  /// Share of this run's failures that the primary cause accounts for, in
  /// [0, 1]. It is measured from the run, not a predicted probability.
  final double confidence;

  bool get hasFailures => categories.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'categories': {for (final e in categories.entries) e.key.name: e.value},
        'primaryCause': primaryCause,
        'secondaryCauses': secondaryCauses,
        'confidence': double.parse(confidence.toStringAsFixed(4)),
        'evidence': evidence,
        'recommendations': recommendations,
      };
}

class FailureAnalyzer {
  const FailureAnalyzer();

  static const _advice = {
    FailureCategory.rejected: 'Return one complete, syntactically valid test file with at least one testWidgets.',
    FailureCategory.undefinedSymbol:
        'A name does not exist. Use only classes, parameters and members shown in the context.',
    FailureCategory.missingImport: 'Fix the imports: use only the URIs listed under "Allowed imports".',
    FailureCategory.compilation: 'Fix the compile errors shown above before changing any test logic.',
    FailureCategory.timeout:
        'Something waits forever. Do not use pumpAndSettle with endless animations or real timers.',
    FailureCategory.noTests: 'Add testWidgets cases; the file currently runs nothing.',
    FailureCategory.finderNotFound:
        'A finder matched nothing. Build finders from texts, icons and keys present in the context, and pump after each action.',
    FailureCategory.pumpAndSettleTimeout:
        'pumpAndSettle never settled because of an ongoing animation or timer; use pump(duration) instead.',
    FailureCategory.missingDependency:
        'A dependency is not registered. Register a fake or test instance before pumping the screen.',
    FailureCategory.layoutOverflow:
        'A layout overflowed in the test viewport. Set a larger size with tester.view.physicalSize, or tolerate the overflow.',
    FailureCategory.assertion: 'Correct the expected values to match what the screen really shows.',
    FailureCategory.runtimeException:
        'The screen threw during the test. Fake the service that throws, or test only what renders without it.',
  };

  FailureAnalysis analyse(TestRun run) {
    final categories = <FailureCategory, int>{};
    void add(FailureCategory category) => categories[category] = (categories[category] ?? 0) + 1;

    if (run.rejectedBeforeExecution) add(FailureCategory.rejected);
    if (run.timedOut) add(FailureCategory.timeout);
    if (!run.compiled && !run.rejectedBeforeExecution) {
      for (final error in run.loadErrors) {
        add(_classifyCompile(error));
      }
      if (run.loadErrors.isEmpty) add(FailureCategory.compilation);
    }
    if (run.compiled && !run.timedOut && run.cases.isEmpty) add(FailureCategory.noTests);
    for (final testCase in run.cases) {
      if (testCase.status == TestCaseStatus.failed) add(_classifyRuntime(testCase.message ?? ''));
    }

    final ordered = categories.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
    final failedNames = [
      for (final c in run.cases)
        if (c.status == TestCaseStatus.failed) c.name,
    ]..sort();

    final total = categories.values.fold<int>(0, (sum, count) => sum + count);
    final messages = <String>[
      ...run.loadErrors,
      for (final c in run.cases)
        if (c.status == TestCaseStatus.failed && c.message != null) c.message!,
    ];
    return FailureAnalysis(
      secondaryCauses: [for (final c in ordered.skip(1)) c.name],
      confidence: total == 0 ? 0 : categories[ordered.first]! / total,
      evidence: [
        for (final message in messages.take(3))
          message.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim(),
      ],
      categories: categories,
      primaryCause: ordered.isEmpty ? 'none' : ordered.first.name,
      recommendations: [for (final c in ordered) _advice[c]!],
      signature: '${ordered.map((c) => c.name).join(',')}|${failedNames.join(',')}',
    );
  }

  static FailureCategory _classifyCompile(String text) {
    if (text.contains('Undefined name') ||
        text.contains("isn't defined") ||
        text.contains('Method not found') ||
        text.contains('No named parameter')) {
      return FailureCategory.undefinedSymbol;
    }
    if (text.contains("Couldn't resolve the package") ||
        text.contains('Not found:') ||
        text.contains('uri_does_not_exist')) {
      return FailureCategory.missingImport;
    }
    return FailureCategory.compilation;
  }

  static FailureCategory _classifyRuntime(String text) {
    if (text.contains('pumpAndSettle timed out')) return FailureCategory.pumpAndSettleTimeout;
    if (text.contains('"') && text.contains('not found') && text.contains('Get.put')) {
      return FailureCategory.missingDependency;
    }
    if (text.contains('ProviderNotFoundException') || text.contains('Could not find the correct Provider')) {
      return FailureCategory.missingDependency;
    }
    if (text.contains('Found 0 widgets') ||
        text.contains('zero widgets') ||
        text.contains('Bad state: No element')) {
      return FailureCategory.finderNotFound;
    }
    if (text.contains('overflowed')) return FailureCategory.layoutOverflow;
    if (text.contains('Expected:')) return FailureCategory.assertion;
    return FailureCategory.runtimeException;
  }
}
