import 'models/test_run.dart';

/// Coverage per source file from an lcov tracefile, keyed by the path relative
/// to the project root with forward slashes (`lib/login.dart`).
class LcovReport {
  LcovReport(this.files, {this.branches = const {}, this.functions = const {}});

  /// File → line → hits.
  final Map<String, Map<int, int>> files;

  /// File → branch id → times taken (`--branch-coverage`).
  final Map<String, Map<String, int>> branches;

  /// File → function name → hits, when the tracefile has them.
  final Map<String, Map<String, int>> functions;

  factory LcovReport.parse(String content, {String? projectPath}) {
    final files = <String, Map<int, int>>{};
    final branches = <String, Map<String, int>>{};
    final functions = <String, Map<String, int>>{};
    Map<int, int>? current;
    String? path;

    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('SF:')) {
        path = normalizePath(line.substring(3), projectPath: projectPath);
        current = files.putIfAbsent(path, () => {});
      } else if (line.startsWith('DA:') && current != null) {
        final parts = line.substring(3).split(',');
        if (parts.length < 2) continue;
        final number = int.tryParse(parts[0]);
        final hits = int.tryParse(parts[1]);
        if (number == null || hits == null) continue;
        current[number] = (current[number] ?? 0) + hits;
      } else if (line.startsWith('BRDA:') && path != null) {
        final parts = line.substring(5).split(',');
        if (parts.length < 4) continue;
        final id = parts.sublist(0, 3).join(',');
        final taken = int.tryParse(parts[3]) ?? 0;
        final map = branches.putIfAbsent(path, () => {});
        map[id] = (map[id] ?? 0) + taken;
      } else if (line.startsWith('FNDA:') && path != null) {
        final comma = line.indexOf(',');
        if (comma < 0) continue;
        final hits = int.tryParse(line.substring(5, comma)) ?? 0;
        final name = line.substring(comma + 1);
        final map = functions.putIfAbsent(path, () => {});
        map[name] = (map[name] ?? 0) + hits;
      } else if (line == 'end_of_record') {
        current = null;
        path = null;
      }
    }
    return LcovReport(files, branches: branches, functions: functions);
  }

  /// lcov may record absolute or relative paths, with either slash.
  static String normalizePath(String path, {String? projectPath}) {
    var normalized = path.replaceAll(r'\', '/');
    if (projectPath != null) {
      final root = '${projectPath.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '')}/';
      if (normalized.toLowerCase().startsWith(root.toLowerCase())) {
        normalized = normalized.substring(root.length);
      }
    }
    return normalized;
  }

  static String _key(String path) => path.replaceAll(r'\', '/');

  LineCoverage? coverageOf(String relativePath) {
    final lines = files[_key(relativePath)];
    if (lines == null) return null;
    return LineCoverage(
      linesFound: lines.length,
      linesHit: lines.values.where((hits) => hits > 0).length,
    );
  }

  Ratio branchesOf(String relativePath) => _ratio(branches[_key(relativePath)]);

  Ratio functionsOf(String relativePath) => _ratio(functions[_key(relativePath)]);

  static Ratio _ratio(Map<String, int>? hits) => hits == null
      ? const Ratio(0, 0)
      : Ratio(hits.values.where((h) => h > 0).length, hits.length);

  /// Union of several reports: a line counts as hit if any report hit it.
  static LcovReport merge(Iterable<LcovReport> reports) {
    final merged = <String, Map<int, int>>{};
    for (final report in reports) {
      report.files.forEach((path, lines) {
        final target = merged.putIfAbsent(path, () => {});
        lines.forEach((line, hits) => target[line] = (target[line] ?? 0) + hits);
      });
    }
    return LcovReport(merged);
  }

  LineCoverage get total {
    var found = 0;
    var hit = 0;
    for (final lines in files.values) {
      found += lines.length;
      hit += lines.values.where((h) => h > 0).length;
    }
    return LineCoverage(linesFound: found, linesHit: hit);
  }
}
