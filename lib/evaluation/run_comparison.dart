import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'statistics.dart';

/// Compares experiment runs from their `results.csv` files, pairing screens by
/// name (Doc 16.10). Two runs get a paired test chosen by the normality of the
/// differences; three or more also get Kruskal–Wallis and ANOVA.
class RunComparison {
  const RunComparison();

  static const metrics = [
    'compiled',
    'all_passed',
    'pass_rate_pct',
    'screen_coverage_pct',
    'branch_coverage_pct',
    'widget_coverage_pct',
    'interaction_coverage_pct',
    'navigation_coverage_pct',
    'state_coverage_pct',
    'assertions_per_test',
    'test_smells',
    'maintainability_index',
    'mutation_score_pct',
    'prompt_tokens',
    'output_tokens',
  ];

  static const alpha = 0.05;

  /// Splits CSV text into rows of column → value.
  static List<Map<String, String>> parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else if (c == '"') {
          quoted = false;
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n') {
        row.add(cell.toString().trimRight());
        cell.clear();
        rows.add(row);
        row = [];
      } else {
        cell.write(c);
      }
    }
    if (rows.isEmpty) return const [];
    final header = rows.first;
    return [
      for (final r in rows.skip(1))
        {for (var i = 0; i < header.length && i < r.length; i++) header[i]: r[i]},
    ];
  }

  static num _number(String? value) =>
      value == 'true' ? 1 : (value == 'false' ? 0 : num.tryParse(value ?? '') ?? 0);

  Map<String, dynamic> compare(Map<String, List<Map<String, String>>> runs) {
    final names = runs.keys.toList();
    final common = runs.values
        .map((rows) => rows.map((r) => r['screen']!).toSet())
        .reduce((a, b) => a.intersection(b))
        .toList()
      ..sort();

    final byScreen = {
      for (final run in names) run: {for (final r in runs[run]!) r['screen']: r},
    };

    final results = <String, dynamic>{};
    for (final metric in metrics) {
      // An empty cell means nothing to measure on that screen, so the screen
      // leaves this metric's pairing in every run.
      final screens = [
        for (final screen in common)
          if (names.every((run) => byScreen[run]![screen]?[metric]?.isNotEmpty ?? false)) screen,
      ];
      final data = {
        for (final run in names)
          run: [for (final screen in screens) _number(byScreen[run]![screen]![metric])],
      };
      final entry = <String, dynamic>{
        'descriptive': {for (final run in names) run: Descriptive(data[run]!).toJson()},
      };

      final pairs = <String, dynamic>{};
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          pairs['${names[i]} vs ${names[j]}'] = _pair(data[names[i]]!, data[names[j]]!);
        }
      }
      entry['pairwise'] = pairs;

      if (names.length > 2 && screens.isNotEmpty) {
        final groups = [for (final run in names) data[run]!];
        final (anova, eta) = oneWayAnova(groups);
        entry['kruskalWallis'] = kruskalWallis(groups).toJson();
        entry['anova'] = anova.toJson();
        entry['etaSquared'] = eta;
      }
      results[metric] = entry;
    }
    return {'runs': names, 'pairedScreens': common.length, 'alpha': alpha, 'metrics': results};
  }

  Map<String, dynamic> _pair(List<num> a, List<num> b) {
    final differences = [for (var i = 0; i < a.length; i++) a[i] - b[i]];
    final normality = shapiroWilk(differences);
    final normal = normality != null && normality.p >= alpha;
    final test = normal ? pairedTTest(a, b) : wilcoxonSignedRank(a, b);
    final delta = cliffsDelta(a, b);
    return {
      'normality': normality?.toJson(),
      'test': test.toJson(),
      'significant': test.p < alpha,
      'cohensD': cohensD(a, b),
      'cliffsDelta': delta,
      'cliffsMagnitude': cliffsMagnitude(delta),
    };
  }

  String toMarkdown(Map<String, dynamic> comparison) {
    String f(num? v) => v == null ? '-' : v.toStringAsFixed(3);
    final out = StringBuffer()
      ..writeln('# Run comparison')
      ..writeln()
      ..writeln('Runs: ${(comparison['runs'] as List).join(', ')}. '
          'Paired screens: ${comparison['pairedScreens']}. α = $alpha.')
      ..writeln();
    final metricsMap = comparison['metrics'] as Map<String, dynamic>;
    for (final entry in metricsMap.entries) {
      out
        ..writeln('## ${entry.key}')
        ..writeln()
        ..writeln('| Run | Mean | Median | SD | 95% CI |')
        ..writeln('|---|---|---|---|---|');
      final descriptive = entry.value['descriptive'] as Map<String, dynamic>;
      descriptive.forEach((run, d) {
        out.writeln('| $run | ${f(d['mean'])} | ${f(d['median'])} | ${f(d['standardDeviation'])} '
            '| [${f(d['ci95'][0])}, ${f(d['ci95'][1])}] |');
      });
      out
        ..writeln()
        ..writeln("| Comparison | Test | p | Significant | Cohen's d | Cliff's δ |")
        ..writeln('|---|---|---|---|---|---|');
      (entry.value['pairwise'] as Map<String, dynamic>).forEach((pair, r) {
        out.writeln('| $pair | ${r['test']['test']} | ${f(r['test']['p'])} | ${r['significant']} '
            '| ${f(r['cohensD'])} | ${f(r['cliffsDelta'])} (${r['cliffsMagnitude']}) |');
      });
      if (entry.value['kruskalWallis'] != null) {
        out
          ..writeln()
          ..writeln('Kruskal-Wallis p = ${f(entry.value['kruskalWallis']['p'])}; '
              'ANOVA p = ${f(entry.value['anova']['p'])}; η² = ${f(entry.value['etaSquared'])}.');
      }
      out.writeln();
    }
    return out.toString();
  }

  /// Merges one setup across a batch's projects. Screens are keyed by project
  /// and screen, so equal names in different apps stay apart. Repetitions
  /// (`pkg-rep1`, `pkg-rep2`) are averaged per screen, because the screen is
  /// the unit of analysis and repeated samples of it are not independent.
  static List<Map<String, String>> mergeBatch(String root, String setup) {
    final repetition = RegExp('^${RegExp.escape(setup)}-rep\\d+\$');
    final samples = <String, List<Map<String, String>>>{};
    final projects = Directory(root).listSync().whereType<Directory>();
    for (final project in projects) {
      final runs = Directory(p.join(project.path, 'runs'));
      if (!runs.existsSync()) continue;
      for (final run in runs.listSync().whereType<Directory>()) {
        final name = p.basename(run.path);
        if (name != setup && !repetition.hasMatch(name)) continue;
        final file = File(p.join(run.path, 'results.csv'));
        if (!file.existsSync()) continue;
        for (final row in parseCsv(file.readAsStringSync().replaceAll('\r\n', '\n'))) {
          samples.putIfAbsent('${p.basename(project.path)}/${row['screen']}', () => []).add(row);
        }
      }
    }
    return [
      for (final entry in samples.entries)
        {
          'screen': entry.key,
          for (final metric in metrics)
            metric: () {
              final values = entry.value.map((r) => r[metric] ?? '').where((v) => v.isNotEmpty);
              return values.isEmpty
                  ? ''
                  : '${values.map(_number).reduce((a, b) => a + b) / values.length}';
            }(),
        },
    ];
  }

  /// Compares setups across all projects of a batch folder.
  Future<void> runBatch(String root, List<String> setups) async {
    final runs = {for (final setup in setups) setup: mergeBatch(root, setup)};
    for (final entry in runs.entries) {
      if (entry.value.isEmpty) throw StateError('No results for "${entry.key}" under $root');
    }
    await _write(compare(runs), Directory(p.join(root, 'comparison')));
  }

  /// Reads `results.csv` from each run directory and writes the comparison.
  Future<void> run(List<String> runDirectories) async {
    final runs = <String, List<Map<String, String>>>{};
    for (final directory in runDirectories) {
      final file = File(p.join(directory, 'results.csv'));
      if (!file.existsSync()) throw StateError('No results.csv in $directory');
      runs[p.basename(p.normalize(directory))] =
          parseCsv((await file.readAsString()).replaceAll('\r\n', '\n'));
    }
    // Next to the runs: <root>/runs/<run> gives <root>/comparison.
    await _write(
        compare(runs),
        Directory(p.join(
            p.dirname(p.dirname(p.normalize(p.absolute(runDirectories.first)))), 'comparison')));
  }

  /// Mean with 95% confidence interval per run, as an SVG bar chart.
  static String figure(String metric, Map<String, dynamic> descriptive) {
    const barWidth = 70, gap = 40, height = 260, top = 40, left = 50;
    final entries = descriptive.entries.toList();
    final highs = [for (final e in entries) (e.value['ci95'][1] as num).toDouble()];
    final maximum = highs.fold<double>(1e-9, (a, b) => a > b ? a : b);
    double y(num value) => top + height - value / maximum * height;
    final width = left + entries.length * (barWidth + gap) + gap;
    final out = StringBuffer('<svg xmlns="http://www.w3.org/2000/svg" width="$width" '
        'height="${top + height + 60}" font-family="sans-serif" font-size="12">'
        '<text x="$left" y="20" font-size="14">$metric</text>'
        '<line x1="$left" y1="${top + height}" x2="$width" y2="${top + height}" stroke="#333"/>');
    for (var i = 0; i < entries.length; i++) {
      final d = entries[i].value;
      final mean = d['mean'] as num;
      final x = left + gap + i * (barWidth + gap);
      final mid = x + barWidth / 2;
      out
        ..write('<rect x="$x" y="${y(mean)}" width="$barWidth" '
            'height="${top + height - y(mean)}" fill="#4878a8"/>')
        ..write('<line x1="$mid" y1="${y(d['ci95'][0] as num)}" x2="$mid" '
            'y2="${y(d['ci95'][1] as num)}" stroke="#000"/>')
        ..write('<text x="$mid" y="${top + height + 16}" text-anchor="middle">${entries[i].key}</text>')
        ..write('<text x="$mid" y="${top + height + 32}" text-anchor="middle">${mean.toStringAsFixed(2)}</text>');
    }
    out.write('</svg>');
    return out.toString();
  }

  Future<void> _write(Map<String, dynamic> comparison, Directory outDir) async {
    outDir.createSync(recursive: true);
    final figures = Directory(p.join(outDir.path, 'figures'))..createSync();
    (comparison['metrics'] as Map<String, dynamic>).forEach((metric, entry) {
      File(p.join(figures.path, '$metric.svg'))
          .writeAsStringSync(figure(metric, entry['descriptive'] as Map<String, dynamic>));
    });
    final markdown = toMarkdown(comparison);
    await File(p.join(outDir.path, 'comparison.json'))
        .writeAsString(const JsonEncoder.withIndent('  ').convert(comparison));
    await File(p.join(outDir.path, 'comparison.md')).writeAsString(markdown);
    print(markdown);
    print('Saved to ${outDir.path}');
  }
}
