import 'dart:convert';

import 'models/test_run.dart';

/// What a `flutter test --reporter json` run reported, minus timing and
/// coverage, which the runner adds.
class ReporterOutcome {
  const ReporterOutcome({
    required this.compiled,
    required this.cases,
    required this.loadErrors,
  });

  final bool compiled;
  final List<TestCaseResult> cases;
  final List<String> loadErrors;
}

/// Parses the machine-readable event stream of `flutter test --reporter
/// json` (one JSON object per line). Counting `testDone` events is exact,
/// unlike scraping the `+N -M` progress line of the human reporter.
class JsonReporterParser {
  const JsonReporterParser();

  static const _maxMessageLength = 2500;

  ReporterOutcome parse(String output) {
    final names = <int, String>{};
    final errors = <int, StringBuffer>{};
    final prints = <int, StringBuffer>{};
    final cases = <TestCaseResult>[];
    final loadErrors = <String>[];
    final otherLines = <String>[];
    var sawLoad = false;
    var loadFailed = false;

    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('{')) {
        if (trimmed.isNotEmpty) otherLines.add(trimmed);
        continue;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        otherLines.add(trimmed);
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;

      switch (decoded['type']) {
        case 'testStart':
          final test = decoded['test'] as Map<String, dynamic>;
          names[test['id'] as int] = test['name'] as String? ?? '';
        case 'error':
          final id = decoded['testID'] as int;
          final stack = (decoded['stackTrace'] as String? ?? '')
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .take(8)
              .join('\n');
          (errors[id] ??= StringBuffer())
            ..writeln(decoded['error'])
            ..writeln(stack);
        case 'print':
          final id = decoded['testID'] as int;
          (prints[id] ??= StringBuffer()).writeln(decoded['message']);
        case 'testDone':
          final id = decoded['testID'] as int;
          final name = names[id] ?? '';
          final result = decoded['result'] as String?;
          if (name.startsWith('loading ')) {
            sawLoad = true;
            if (result != 'success') {
              loadFailed = true;
              loadErrors.add(_truncate('${errors[id] ?? ''}${prints[id] ?? ''}'.trim()));
            }
            continue;
          }
          if (decoded['hidden'] == true && result == 'success') continue;

          final status = decoded['skipped'] == true
              ? TestCaseStatus.skipped
              : result == 'success'
                  ? TestCaseStatus.passed
                  : TestCaseStatus.failed;
          final message = status == TestCaseStatus.failed
              ? _truncate('${errors[id] ?? ''}${prints[id] ?? ''}'.trim())
              : null;
          cases.add(TestCaseResult(name: name, status: status, message: message));
      }
    }

    // No load event at all means the tool failed before running the file,
    // e.g. a compile error reported outside the JSON stream.
    if (!sawLoad && cases.isEmpty) {
      loadFailed = true;
      loadErrors.add(_truncate(otherLines.join('\n')));
    }

    return ReporterOutcome(compiled: !loadFailed, cases: cases, loadErrors: loadErrors);
  }

  static String _truncate(String text) => text.length <= _maxMessageLength
      ? text
      : '${text.substring(0, _maxMessageLength)}\n... (truncated)';
}
