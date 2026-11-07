import 'package:flutterastest/execution/lcov.dart';
import 'package:test/test.dart';

void main() {
  const tracefile = '''
SF:lib/login.dart
DA:1,1
DA:2,0
DA:3,4
LF:3
LH:2
end_of_record
SF:C:\\proj\\lib\\home.dart
DA:5,0
DA:6,0
end_of_record
''';

  test('parses line hits and normalizes absolute Windows paths', () {
    final report = LcovReport.parse(tracefile, projectPath: r'C:\proj');
    expect(report.files.keys, unorderedEquals(['lib/login.dart', 'lib/home.dart']));

    final login = report.coverageOf('lib/login.dart')!;
    expect(login.linesFound, 3);
    expect(login.linesHit, 2);
    expect(report.coverageOf(r'lib\login.dart')!.linesHit, 2);
    expect(report.coverageOf('lib/missing.dart'), isNull);
  });

  test('merge counts a line as hit when any report hit it', () {
    final first = LcovReport.parse(tracefile, projectPath: r'C:\proj');
    final second = LcovReport.parse('SF:lib/home.dart\nDA:5,2\nDA:7,0\nend_of_record\n');

    final merged = LcovReport.merge([first, second]);
    expect(merged.coverageOf('lib/home.dart')!.linesHit, 1);
    expect(merged.coverageOf('lib/home.dart')!.linesFound, 3);
    expect(merged.total.linesFound, 6);
    expect(merged.total.linesHit, 3);
    expect(merged.total.ratio, closeTo(0.5, 1e-9));
  });
}
