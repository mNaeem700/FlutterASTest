import 'dart:convert';

import 'package:flutterastest/execution/json_reporter_parser.dart';
import 'package:flutterastest/execution/models/test_run.dart';
import 'package:test/test.dart';

String events(List<Map<String, dynamic>> list) => list.map(jsonEncode).join('\n');

Map<String, dynamic> start(int id, String name) => {
      'type': 'testStart',
      'test': {'id': id, 'name': name},
    };

Map<String, dynamic> done(int id, String result, {bool hidden = false, bool skipped = false}) => {
      'type': 'testDone',
      'testID': id,
      'result': result,
      'hidden': hidden,
      'skipped': skipped,
    };

void main() {
  const parser = JsonReporterParser();

  test('counts passed, failed and skipped tests and keeps failure messages', () {
    final outcome = parser.parse(events([
      {'type': 'start'},
      start(1, 'loading test/a_test.dart'),
      done(1, 'success', hidden: true),
      start(2, 'renders'),
      done(2, 'success'),
      start(3, 'taps login'),
      {'type': 'print', 'testID': 3, 'message': 'EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK'},
      {'type': 'error', 'testID': 3, 'error': 'Expected: exactly one matching candidate', 'stackTrace': 'at line 12'},
      done(3, 'failure'),
      start(4, 'skipped one'),
      done(4, 'success', skipped: true),
      {'type': 'done', 'success': false},
    ]));

    expect(outcome.compiled, isTrue);
    expect(outcome.cases.map((c) => c.status), [
      TestCaseStatus.passed,
      TestCaseStatus.failed,
      TestCaseStatus.skipped,
    ]);
    final failed = outcome.cases[1];
    expect(failed.name, 'taps login');
    expect(failed.message, contains('exactly one matching candidate'));
    expect(failed.message, contains('EXCEPTION CAUGHT'));
  });

  test('a failed loading test means the file did not compile', () {
    final outcome = parser.parse(events([
      start(1, 'loading test/a_test.dart'),
      {'type': 'error', 'testID': 1, 'error': "Error: Method not found: 'LoginScren'.", 'stackTrace': ''},
      done(1, 'error'),
    ]));

    expect(outcome.compiled, isFalse);
    expect(outcome.cases, isEmpty);
    expect(outcome.loadErrors.single, contains('LoginScren'));
  });

  test('output without any JSON events is a tool failure, not a pass', () {
    final outcome = parser.parse('Error: No pubspec.yaml file found.\n');
    expect(outcome.compiled, isFalse);
    expect(outcome.loadErrors.single, contains('No pubspec.yaml'));
  });

  test('a hidden setUpAll failure is reported as a failed case', () {
    final outcome = parser.parse(events([
      start(1, 'loading test/a_test.dart'),
      done(1, 'success', hidden: true),
      start(2, '(setUpAll)'),
      {'type': 'error', 'testID': 2, 'error': 'Get.find failed', 'stackTrace': ''},
      done(2, 'error', hidden: true),
    ]));
    expect(outcome.cases.single.status, TestCaseStatus.failed);
  });
}
