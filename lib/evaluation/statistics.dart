import 'dart:math';

/// The statistical procedures of Doc 16.10, in pure Dart so the replication
/// package needs no other runtime. All p-values are two-sided.
class Descriptive {
  Descriptive(List<num> data) : values = [for (final v in data) v.toDouble()]..sort();

  final List<double> values;

  int get n => values.length;
  double get mean => n == 0 ? 0 : values.reduce((a, b) => a + b) / n;

  double get median {
    if (n == 0) return 0;
    final mid = n ~/ 2;
    return n.isOdd ? values[mid] : (values[mid - 1] + values[mid]) / 2;
  }

  double get variance {
    if (n < 2) return 0;
    final m = mean;
    return values.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) / (n - 1);
  }

  double get standardDeviation => sqrt(variance);

  /// 95% confidence interval of the mean, from the t distribution.
  (double, double) get confidenceInterval95 {
    if (n < 2) return (mean, mean);
    final margin = tCritical95(n - 1) * standardDeviation / sqrt(n);
    return (mean - margin, mean + margin);
  }

  Map<String, dynamic> toJson() => {
        'n': n,
        'mean': mean,
        'median': median,
        'standardDeviation': standardDeviation,
        'variance': variance,
        'ci95': [confidenceInterval95.$1, confidenceInterval95.$2],
      };
}

class TestResult {
  const TestResult(this.test, this.statistic, this.p);

  final String test;
  final double statistic;
  final double p;

  Map<String, dynamic> toJson() => {'test': test, 'statistic': statistic, 'p': p};
}

double normalCdf(double z) => 0.5 * _erfc(-z / sqrt2);

/// Complementary error function (Numerical Recipes, fractional error < 1.2e-7).
double _erfc(double x) {
  final z = x.abs();
  final t = 1 / (1 + 0.5 * z);
  final r = t *
      exp(-z * z -
          1.26551223 +
          t *
              (1.00002368 +
                  t *
                      (0.37409196 +
                          t *
                              (0.09678418 +
                                  t *
                                      (-0.18628806 +
                                          t *
                                              (0.27886807 +
                                                  t *
                                                      (-1.13520398 +
                                                          t *
                                                              (1.48851587 +
                                                                  t *
                                                                      (-0.82215223 +
                                                                          t * 0.17087277)))))))));
  return x >= 0 ? r : 2 - r;
}

double inverseNormal(double p) {
  var low = -40.0, high = 40.0;
  for (var i = 0; i < 200; i++) {
    final mid = (low + high) / 2;
    if (normalCdf(mid) < p) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return (low + high) / 2;
}

double _logGamma(double x) {
  const c = [76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155,
      0.1208650973866179e-2, -0.5395239384953e-5];
  var y = x;
  var tmp = x + 5.5;
  tmp -= (x + 0.5) * log(tmp);
  var series = 1.000000000190015;
  for (final value in c) {
    series += value / ++y;
  }
  return -tmp + log(2.5066282746310005 * series / x);
}

/// Regularized incomplete beta function I_x(a, b).
double incompleteBeta(double a, double b, double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final front = exp(_logGamma(a + b) - _logGamma(a) - _logGamma(b) + a * log(x) + b * log(1 - x));
  return x < (a + 1) / (a + b + 2)
      ? front * _betaContinuedFraction(a, b, x) / a
      : 1 - front * _betaContinuedFraction(b, a, 1 - x) / b;
}

double _betaContinuedFraction(double a, double b, double x) {
  const tiny = 1e-300;
  var c = 1.0;
  var d = 1 - (a + b) * x / (a + 1);
  if (d.abs() < tiny) d = tiny;
  d = 1 / d;
  var h = d;
  for (var m = 1; m <= 500; m++) {
    final m2 = 2 * m;
    var aa = m * (b - m) * x / ((a + m2 - 1) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (a + b + m) * x / ((a + m2) * (a + m2 + 1));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < 1e-12) break;
  }
  return h;
}

/// Two-sided p-value of a t statistic.
double tTwoSidedP(double t, double df) => incompleteBeta(df / 2, 0.5, df / (df + t * t));

double tCritical95(int df) {
  var low = 0.0, high = 1000.0;
  for (var i = 0; i < 200; i++) {
    final mid = (low + high) / 2;
    if (tTwoSidedP(mid, df.toDouble()) > 0.05) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return (low + high) / 2;
}

/// Upper tail of the F distribution.
double fUpperP(double f, double df1, double df2) =>
    f <= 0 ? 1 : incompleteBeta(df2 / 2, df1 / 2, df2 / (df2 + df1 * f));

/// Upper tail of the chi-square distribution.
double chiSquareUpperP(double x, double df) {
  if (x <= 0) return 1;
  final a = df / 2, z = x / 2;
  if (z < a + 1) {
    var sum = 1 / a, term = sum, n = a;
    for (var i = 0; i < 1000; i++) {
      n += 1;
      term *= z / n;
      sum += term;
      if (term.abs() < sum.abs() * 1e-14) break;
    }
    return 1 - sum * exp(-z + a * log(z) - _logGamma(a));
  }
  const tiny = 1e-300;
  var b = z + 1 - a, c = 1 / tiny, d = 1 / b, h = d;
  for (var i = 1; i <= 1000; i++) {
    final an = -i * (i - a);
    b += 2;
    d = an * d + b;
    if (d.abs() < tiny) d = tiny;
    c = b + an / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final delta = d * c;
    h *= delta;
    if ((delta - 1).abs() < 1e-14) break;
  }
  return exp(-z + a * log(z) - _logGamma(a)) * h;
}

/// Shapiro–Wilk normality test (Royston 1995, AS R94). Null for n < 3 or
/// constant data, where the test is undefined.
TestResult? shapiroWilk(List<num> data) {
  final x = [for (final v in data) v.toDouble()]..sort();
  final n = x.length;
  if (n < 3 || x.first == x.last) return null;

  final m = [for (var i = 1; i <= n; i++) inverseNormal((i - 0.375) / (n + 0.25))];
  final mm = m.map((v) => v * v).reduce((a, b) => a + b);
  final u = 1 / sqrt(n);
  final a = List<double>.filled(n, 0);

  if (n == 3) {
    a[0] = -sqrt1_2;
    a[2] = sqrt1_2;
  } else {
    final an = -2.706056 * pow(u, 5) + 4.434685 * pow(u, 4) - 2.071190 * pow(u, 3) -
        0.147981 * u * u + 0.221157 * u + m[n - 1] / sqrt(mm);
    a[n - 1] = an;
    a[0] = -an;
    int first;
    double eps;
    if (n > 5) {
      final an1 = -3.582633 * pow(u, 5) + 5.682633 * pow(u, 4) - 1.752461 * pow(u, 3) -
          0.293762 * u * u + 0.042981 * u + m[n - 2] / sqrt(mm);
      a[n - 2] = an1;
      a[1] = -an1;
      first = 2;
      eps = (mm - 2 * m[n - 1] * m[n - 1] - 2 * m[n - 2] * m[n - 2]) /
          (1 - 2 * an * an - 2 * an1 * an1);
    } else {
      first = 1;
      eps = (mm - 2 * m[n - 1] * m[n - 1]) / (1 - 2 * an * an);
    }
    for (var i = first; i < n - first; i++) {
      a[i] = m[i] / sqrt(eps);
    }
  }

  final mean = x.reduce((p, q) => p + q) / n;
  var numerator = 0.0, denominator = 0.0;
  for (var i = 0; i < n; i++) {
    numerator += a[i] * x[i];
    denominator += (x[i] - mean) * (x[i] - mean);
  }
  final w = min(1.0, numerator * numerator / denominator);

  double p;
  if (n == 3) {
    p = max(0.0, 6 / pi * (asin(sqrt(w)) - asin(sqrt(0.75))));
  } else {
    final y = log(1 - w);
    double z;
    if (n <= 11) {
      final gamma = -2.273 + 0.459 * n;
      if (y >= gamma) return TestResult('Shapiro-Wilk', w, 0);
      final mu = 0.5440 - 0.39978 * n + 0.025054 * n * n - 0.0006714 * n * n * n;
      final sigma = exp(1.3822 - 0.77857 * n + 0.062767 * n * n - 0.0020322 * n * n * n);
      z = (-log(gamma - y) - mu) / sigma;
    } else {
      final l = log(n);
      final mu = -1.5861 - 0.31082 * l - 0.083751 * l * l + 0.0038915 * l * l * l;
      final sigma = exp(-0.4803 - 0.082676 * l + 0.0030302 * l * l);
      z = (y - mu) / sigma;
    }
    p = 1 - normalCdf(z);
  }
  return TestResult('Shapiro-Wilk', w, p);
}

/// Mean ranks with ties averaged, in input order.
List<double> _ranks(List<double> values) {
  final order = List.generate(values.length, (i) => i)
    ..sort((a, b) => values[a].compareTo(values[b]));
  final ranks = List<double>.filled(values.length, 0);
  var i = 0;
  while (i < order.length) {
    var j = i;
    while (j + 1 < order.length && values[order[j + 1]] == values[order[i]]) {
      j++;
    }
    final rank = (i + j) / 2 + 1;
    for (var k = i; k <= j; k++) {
      ranks[order[k]] = rank;
    }
    i = j + 1;
  }
  return ranks;
}

double _tieTerm(List<double> values) {
  final counts = <double, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  return counts.values.fold(0.0, (sum, t) => sum + (t * t * t - t));
}

TestResult pairedTTest(List<num> a, List<num> b) {
  final d = Descriptive([for (var i = 0; i < a.length; i++) a[i] - b[i]]);
  if (d.standardDeviation == 0) return TestResult('Paired t-test', 0, d.mean == 0 ? 1 : 0);
  final t = d.mean / (d.standardDeviation / sqrt(d.n));
  return TestResult('Paired t-test', t, tTwoSidedP(t, d.n - 1.0));
}

/// Welch's t-test, which does not assume equal variances.
TestResult studentTTest(List<num> a, List<num> b) {
  final x = Descriptive(a), y = Descriptive(b);
  final vx = x.variance / x.n, vy = y.variance / y.n;
  if (vx + vy == 0) return TestResult("Welch's t-test", 0, x.mean == y.mean ? 1 : 0);
  final t = (x.mean - y.mean) / sqrt(vx + vy);
  final df = (vx + vy) * (vx + vy) / (vx * vx / (x.n - 1) + vy * vy / (y.n - 1));
  return TestResult("Welch's t-test", t, tTwoSidedP(t, df));
}

/// Wilcoxon signed-rank test; zero differences are dropped. Exact without ties
/// for n <= 25, otherwise the normal approximation with tie and continuity
/// corrections.
TestResult wilcoxonSignedRank(List<num> a, List<num> b) {
  final d = [
    for (var i = 0; i < a.length; i++)
      if (a[i] != b[i]) (a[i] - b[i]).toDouble(),
  ];
  final n = d.length;
  if (n == 0) return const TestResult('Wilcoxon signed-rank', 0, 1);
  final absolute = d.map((v) => v.abs()).toList();
  final ranks = _ranks(absolute);
  var plus = 0.0;
  for (var i = 0; i < n; i++) {
    if (d[i] > 0) plus += ranks[i];
  }
  final total = n * (n + 1) / 2;
  final statistic = min(plus, total - plus);
  final ties = _tieTerm(absolute);

  if (ties == 0 && n <= 25) {
    var counts = List<double>.filled(total.toInt() + 1, 0)..[0] = 1;
    for (var rank = 1; rank <= n; rank++) {
      final next = List<double>.of(counts);
      for (var s = rank; s < counts.length; s++) {
        next[s] += counts[s - rank];
      }
      counts = next;
    }
    final tail = counts.take(statistic.toInt() + 1).reduce((x, y) => x + y) / pow(2, n);
    return TestResult('Wilcoxon signed-rank (exact)', statistic, min(1.0, 2 * tail));
  }

  final mean = total / 2;
  final variance = n * (n + 1) * (2 * n + 1) / 24 - ties / 48;
  if (variance <= 0) return TestResult('Wilcoxon signed-rank', statistic, 1);
  final z = max(0.0, (plus - mean).abs() - 0.5) / sqrt(variance);
  return TestResult('Wilcoxon signed-rank', statistic, min(1.0, 2 * (1 - normalCdf(z))));
}

/// Mann–Whitney U test, normal approximation with tie and continuity corrections.
TestResult mannWhitneyU(List<num> a, List<num> b) {
  final all = [for (final v in [...a, ...b]) v.toDouble()];
  final ranks = _ranks(all);
  final n1 = a.length, n2 = b.length, n = n1 + n2;
  final r1 = ranks.take(n1).fold(0.0, (x, y) => x + y);
  final u1 = r1 - n1 * (n1 + 1) / 2;
  final u = min(u1, n1 * n2 - u1);
  final variance = n1 * n2 / 12 * (n + 1 - _tieTerm(all) / (n * (n - 1)));
  if (variance <= 0) return TestResult('Mann-Whitney U', u, 1);
  final z = max(0.0, (u1 - n1 * n2 / 2).abs() - 0.5) / sqrt(variance);
  return TestResult('Mann-Whitney U', u, min(1.0, 2 * (1 - normalCdf(z))));
}

TestResult kruskalWallis(List<List<num>> groups) {
  final all = [for (final g in groups) for (final v in g) v.toDouble()];
  final n = all.length;
  final ranks = _ranks(all);
  var h = 0.0, offset = 0;
  for (final group in groups) {
    final sum = ranks.skip(offset).take(group.length).fold(0.0, (x, y) => x + y);
    h += sum * sum / group.length;
    offset += group.length;
  }
  h = 12 / (n * (n + 1)) * h - 3 * (n + 1);
  final correction = 1 - _tieTerm(all) / (n * n * n - n);
  if (correction <= 0) return const TestResult('Kruskal-Wallis', 0, 1);
  h /= correction;
  return TestResult('Kruskal-Wallis', h, chiSquareUpperP(h, groups.length - 1.0));
}

/// One-way ANOVA; also returns the effect size eta squared.
(TestResult, double) oneWayAnova(List<List<num>> groups) {
  final all = Descriptive([for (final g in groups) ...g]);
  var between = 0.0, within = 0.0;
  for (final group in groups) {
    final d = Descriptive(group);
    between += d.n * (d.mean - all.mean) * (d.mean - all.mean);
    within += d.variance * (d.n - 1);
  }
  final df1 = groups.length - 1.0, df2 = all.n - groups.length.toDouble();
  final total = between + within;
  final eta = total == 0 ? 0.0 : between / total;
  if (within == 0 || df2 <= 0) return (const TestResult('One-way ANOVA', 0, 1), eta);
  final f = (between / df1) / (within / df2);
  return (TestResult('One-way ANOVA', f, fUpperP(f, df1, df2)), eta);
}

/// Cohen's d of two groups, from the pooled standard deviation.
double cohensD(List<num> a, List<num> b) {
  final x = Descriptive(a), y = Descriptive(b);
  final df = x.n + y.n - 2;
  if (df <= 0) return 0;
  final pooled = sqrt(((x.n - 1) * x.variance + (y.n - 1) * y.variance) / df);
  return pooled == 0 ? 0 : (x.mean - y.mean) / pooled;
}

/// Cliff's delta in [-1, 1]: how often values of [a] exceed values of [b].
double cliffsDelta(List<num> a, List<num> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var more = 0, less = 0;
  for (final x in a) {
    for (final y in b) {
      if (x > y) more++;
      if (x < y) less++;
    }
  }
  return (more - less) / (a.length * b.length);
}

/// Romano et al.'s thresholds for Cliff's delta.
String cliffsMagnitude(double delta) {
  final d = delta.abs();
  return d < 0.147 ? 'negligible' : d < 0.33 ? 'small' : d < 0.474 ? 'medium' : 'large';
}
