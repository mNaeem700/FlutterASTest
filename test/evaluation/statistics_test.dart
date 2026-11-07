import 'package:flutterastest/evaluation/run_comparison.dart';
import 'package:flutterastest/evaluation/statistics.dart';
import 'package:flutterastest/evaluation/extraction_accuracy.dart';
import 'package:flutterastest/evaluation/test_quality_analyzer.dart';
import 'package:test/test.dart';

void main() {
  group('distributions match standard table values', () {
    test('normal', () => expect(normalCdf(1.96), closeTo(0.975, 1e-3)));
    test('t', () {
      expect(tTwoSidedP(2.228, 10), closeTo(0.05, 1e-3));
      expect(tCritical95(10), closeTo(2.228, 1e-3));
    });
    test('chi-square', () => expect(chiSquareUpperP(3.841, 1), closeTo(0.05, 1e-3)));
    test('F', () => expect(fUpperP(4.256, 2, 9), closeTo(0.05, 1e-3)));
  });

  test('descriptive statistics', () {
    final d = Descriptive([2, 4, 4, 4, 5, 5, 7, 9]);
    expect(d.mean, 5);
    expect(d.median, 4.5);
    expect(d.variance, closeTo(4.571, 1e-3));
  });

  test("Wilcoxon exact on Darwin's plant data", () {
    const d = [6, 8, 14, 16, 23, 24, 28, 29, 41, -48, 49, 56, 60, -67, 75];
    final r = wilcoxonSignedRank(d, List.filled(d.length, 0));
    expect(r.statistic, 24);
    expect(r.p, closeTo(0.0413, 1e-3));
  });

  test('Mann-Whitney on fully separated groups', () {
    final r = mannWhitneyU([1, 2, 3, 4, 5], [6, 7, 8, 9, 10]);
    expect(r.statistic, 0);
    expect(r.p, closeTo(0.0122, 1e-3));
  });

  test('effect sizes', () {
    expect(cliffsDelta([6, 7], [1, 2]), 1);
    expect(cliffsDelta([1, 2], [1, 2]), 0);
    expect(cliffsMagnitude(0.5), 'large');
    expect(cohensD([1, 2, 3], [2, 3, 4]), closeTo(-1, 1e-9));
  });

  test('Shapiro-Wilk separates normal-like from skewed data', () {
    final normalLike = [-1.5, -1.0, -0.7, -0.4, -0.2, 0.0, 0.2, 0.4, 0.7, 1.0, 1.5, -0.1, 0.1];
    expect(shapiroWilk(normalLike)!.p, greaterThan(0.05));
    final skewed = [1, 1, 1, 1, 2, 2, 2, 3, 3, 5, 8, 20, 90];
    expect(shapiroWilk(skewed)!.p, lessThan(0.01));
    expect(shapiroWilk([1, 1, 1]), isNull);
  });

  test('group tests', () {
    final groups = <List<num>>[
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ];
    final (anova, eta) = oneWayAnova(groups);
    expect(anova.statistic, closeTo(27, 1e-9));
    expect(eta, closeTo(0.9, 1e-9));
    expect(kruskalWallis(groups).p, lessThan(0.05));
  });

  test('comparison pairs screens by name and parses quoted CSV', () {
    final rows = RunComparison.parseCsv('screen,all_passed,note\nA,true,"x,y"\nB,false,z\n');
    expect(rows.first['note'], 'x,y');
    final result = const RunComparison().compare({
      'one': rows,
      'two': RunComparison.parseCsv('screen,all_passed\nB,true\nA,true\nC,true\n'),
    });
    expect(result['pairedScreens'], 2);
    expect(result['metrics']['all_passed']['descriptive']['two']['mean'], 1);
  });

  test('extraction accuracy', () {
    final s = ExtractionAccuracy.score({'a', 'b'}, {'b', 'c', 'd'});
    expect(s['precision'], 0.5);
    expect(s['recall'], closeTo(1 / 3, 1e-9));
    expect(s['f1'], closeTo(0.4, 1e-9));
  });

  test('maintainability falls as a test file grows and branches', () {
    final small = const TestQualityAnalyzer().analyse("void main() { test('a', () { expect(1, 1); }); }");
    final body = List.generate(40, (i) => "  test('t$i', () { if (true && false) { expect($i, $i); } });").join('\n');
    final large = const TestQualityAnalyzer().analyse('void main() {\n$body\n}');
    expect(large.maintainabilityIndex, lessThan(small.maintainabilityIndex));
  });

  test('test quality finds assertions and smells', () {
    final q = const TestQualityAnalyzer().analyse(r'''
void main() {
  testWidgets('a', (tester) async { expect(1, 1); });
  testWidgets('b', (tester) async { print('x'); });
  testWidgets('c', (tester) async {
    await Future.delayed(Duration(seconds: 1));
    if (true) { expect(1, 1); }
  });
  testWidgets('d', (tester) async { expect(1, 1); });
}
''');
    expect(q.tests, 4);
    expect(q.assertions, 3);
    expect(q.smells['noAssertion'], 1);
    expect(q.smells['printStatement'], 1);
    expect(q.smells['sleepyTest'], 1);
    expect(q.smells['conditionalLogic'], 1);
    expect(q.smells['duplicateTest'], 1);
    expect(q.maintainabilityIndex, inInclusiveRange(1, 100));
  });
}
