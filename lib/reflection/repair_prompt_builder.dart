import '../execution/models/test_run.dart';
import 'failure_analyzer.dart';

/// Builds the refined prompt of the reflection loop: the original prompt, the
/// test file so far, what happened when it ran, the diagnosis and, with
/// coverage guidance, what the tests do not exercise yet.
class RepairPromptBuilder {
  const RepairPromptBuilder();

  static const _maxFeedbackLength = 6000;

  String build({
    required String originalPrompt,
    required String previousCode,
    required TestRun run,
    required int iteration,
    FailureAnalysis? analysis,
    bool coverageGuided = false,
    Map<String, String> classImports = const {},
  }) {
    final out = StringBuffer()
      ..writeln(originalPrompt.trimRight())
      ..writeln()
      ..writeln('## Previous attempt (iteration ${iteration - 1})')
      ..writeln('```dart')
      ..writeln(previousCode.trimRight())
      ..writeln('```')
      ..writeln()
      ..writeln('## Result of running it with `flutter test`')
      ..writeln(_truncate(feedback(run)));

    if (analysis != null && analysis.hasFailures) {
      out
        ..writeln()
        ..writeln('## Diagnosis')
        ..writeln('Primary cause: ${analysis.primaryCause} '
            '(${(analysis.confidence * 100).round()}% of the failures)');
      for (final recommendation in analysis.recommendations) {
        out.writeln('- $recommendation');
      }
    }

    final imports = importsForMissingNames(run, classImports);
    if (imports.isNotEmpty) {
      out
        ..writeln()
        ..writeln('## Imports for names the compiler could not find')
        ..writeln('These project imports are also allowed:');
      imports.forEach((name, uri) => out.writeln("- `$name`: `import '$uri';`"));
    }

    final gaps = coverageGuided ? coverageGaps(run) : '';
    if (gaps.isNotEmpty) {
      out
        ..writeln()
        ..writeln('## Not covered yet')
        ..writeln(gaps);
    }

    out
      ..writeln()
      ..writeln('## Repair task')
      ..writeln('Improve the test file so that it compiles, its tests pass against the real screen'
          '${gaps.isEmpty ? '' : ', and it exercises the behaviour listed under "Not covered yet"'}.')
      ..writeln('- Keep the tests that already pass unchanged.')
      ..writeln('- Fix wrong finders, imports, setup and timing according to the errors above.')
      ..writeln('- Do not delete a failing test or weaken its assertions just to make the run pass. '
          'Remove it only if the behaviour cannot be tested without real network, storage or '
          'platform services, and say why in a code comment.')
      ..writeln('- Follow all rules above, and reply with the whole corrected file in exactly one ```dart code block.');
    return out.toString();
  }

  static Map<String, String> importsForMissingNames(TestRun run, Map<String, String> classImports) {
    final pattern = RegExp(r"(?:not found|Undefined name|Undefined class|isn't defined[^']*|Type)[:\s]*'(\w+)'");
    final found = <String, String>{};
    for (final error in run.loadErrors) {
      for (final match in pattern.allMatches(error)) {
        final uri = classImports[match.group(1)];
        if (uri != null) found[match.group(1)!] = uri;
      }
    }
    return found;
  }

  /// Plain-text summary of a run, as the LLM sees it.
  static String feedback(TestRun run) {
    final out = StringBuffer();
    if (run.timedOut) {
      out.writeln('The run timed out. A test probably waits forever, e.g. `pumpAndSettle` '
          'with an endless animation or a real timer or network call.');
    }
    if (!run.compiled) {
      out.writeln('The file failed to compile or load:');
      for (final error in run.loadErrors) {
        out.writeln(error);
      }
      return out.toString().trim();
    }
    if (run.cases.isEmpty) {
      out.writeln('The file compiled but contains no tests.');
      return out.toString().trim();
    }

    out.writeln('${run.passed} test(s) passed, ${run.failed} failed.');
    for (final testCase in run.cases) {
      if (testCase.status == TestCaseStatus.passed) {
        out.writeln('PASSED: ${testCase.name}');
      }
    }
    for (final testCase in run.cases) {
      if (testCase.status == TestCaseStatus.failed) {
        out
          ..writeln()
          ..writeln('FAILED: ${testCase.name}')
          ..writeln(testCase.message ?? '(no message)');
      }
    }
    return out.toString().trim();
  }

  /// Uncovered behaviour of the screen from the structural coverage report.
  static String coverageGaps(TestRun run) {
    final structural = run.structural;
    if (structural == null) return '';
    String section(String title, List<String> items) =>
        items.isEmpty ? '' : '$title:\n${items.map((i) => '- $i').join('\n')}\n';
    return [
      section('User interactions never triggered', structural.uncoveredInteractions),
      section('Navigation never reached', structural.uncoveredNavigation),
      section('State changes never reached', structural.uncoveredState),
    ].join().trim();
  }

  static String _truncate(String text) => text.length <= _maxFeedbackLength
      ? text
      : '${text.substring(0, _maxFeedbackLength)}\n... (truncated)';
}
