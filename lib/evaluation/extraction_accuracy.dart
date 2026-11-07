import 'dart:convert';
import 'dart:io';

/// RQ1: compares extracted screen contexts with a manually annotated ground
/// truth and reports precision, recall and F1 per kind of fact.
///
/// Ground truth format:
/// `{"screens": [{"name": "Login", "navigation": ["Home"],
///   "interactions": [{"widget": "ElevatedButton", "event": "onPressed"}]}]}`
class ExtractionAccuracy {
  const ExtractionAccuracy();

  static Map<String, double> score(Set<String> predicted, Set<String> truth) {
    final correct = predicted.intersection(truth).length;
    final precision = predicted.isEmpty ? 0.0 : correct / predicted.length;
    final recall = truth.isEmpty ? 0.0 : correct / truth.length;
    final f1 = precision + recall == 0 ? 0.0 : 2 * precision * recall / (precision + recall);
    return {
      'predicted': predicted.length.toDouble(),
      'truth': truth.length.toDouble(),
      'correct': correct.toDouble(),
      'precision': precision,
      'recall': recall,
      'f1': f1,
    };
  }

  Map<String, Map<String, double>> compare(List<dynamic> predicted, Map<String, dynamic> truth) {
    final annotated = truth['screens'] as List<dynamic>;
    return {
      'screens': score(
        {for (final s in predicted) s['name'] as String},
        {for (final s in annotated) s['name'] as String},
      ),
      'navigation': score(
        {
          for (final s in predicted)
            for (final n in s['navigation'] as List<dynamic>)
              if (n['target'] != null) '${s['name']}->${n['target']}',
        },
        {
          for (final s in annotated)
            for (final n in (s['navigation'] as List<dynamic>? ?? const [])) '${s['name']}->$n',
        },
      ),
      'interactions': score(
        {
          for (final s in predicted)
            for (final i in s['interactions'] as List<dynamic>)
              '${s['name']}/${i['widgetType']}.${i['event']}',
        },
        {
          for (final s in annotated)
            for (final i in (s['interactions'] as List<dynamic>? ?? const []))
              '${s['name']}/${i['widget']}.${i['event']}',
        },
      ),
    };
  }

  Future<void> run(String predictedPath, String truthPath) async {
    final predicted = jsonDecode(await File(predictedPath).readAsString());
    final truth = jsonDecode(await File(truthPath).readAsString()) as Map<String, dynamic>;
    final screens = predicted is Map ? predicted['screens'] as List<dynamic> : predicted as List<dynamic>;
    final result = compare(screens, truth);
    print('Fact           Precision  Recall     F1');
    result.forEach((kind, s) {
      String f(String key) => s[key]!.toStringAsFixed(3).padRight(11);
      print('${kind.padRight(15)}${f('precision')}${f('recall')}${f('f1')}');
    });
    final out = File('output/analysis/extraction_accuracy.json')..parent.createSync(recursive: true);
    await out.writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    print('Saved to ${out.path}');
  }
}
