import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../analysis/analysis_result.dart';
import 'models/prompt_context.dart';

/// Source-based contexts for the comparison groups of Doc 16.6, with no AST or
/// PKG information. The prompt template around them is identical to the PKG
/// mode, so only the context differs.
class BaselineContextGenerator {
  const BaselineContextGenerator();

  /// Group A: the raw source file of each screen.
  List<PromptContext> generate(AnalysisResult analysis, {required String projectPath}) =>
      _contexts(analysis, projectPath, (screenFile, source, imports) => _fence(source));

  /// Group B: the screen file followed by the project files it imports.
  List<PromptContext> generateFileLevel(AnalysisResult analysis, {required String projectPath}) {
    final package = analysis.projectInfo.packageName;
    return _contexts(analysis, projectPath, (screenFile, source, imports) {
      final out = StringBuffer(_section(p.relative(screenFile, from: projectPath), source));
      for (final uri in imports) {
        final path = p.joinAll([
          projectPath,
          'lib',
          ...uri.substring('package:$package/'.length).split('/'),
        ]);
        final file = File(path);
        if (file.existsSync()) {
          out.write('\n\n${_section(p.relative(path, from: projectPath), file.readAsStringSync())}');
        }
      }
      return out.toString();
    });
  }

  /// Baseline 4: every Dart file under lib/, the screen file first.
  List<PromptContext> generateRepository(AnalysisResult analysis, {required String projectPath}) {
    final files = Directory(p.join(projectPath, 'lib'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path)
        .toList()
      ..sort();
    return _contexts(analysis, projectPath, (screenFile, source, imports) {
      final out = StringBuffer(_section(p.relative(screenFile, from: projectPath), source));
      for (final path in files) {
        if (p.equals(path, screenFile)) continue;
        out.write('\n\n${_section(p.relative(path, from: projectPath), File(path).readAsStringSync())}');
      }
      return out.toString();
    });
  }

  List<PromptContext> _contexts(AnalysisResult analysis, String projectPath,
      String Function(String screenFile, String source, List<String> imports) render) {
    final contexts = <PromptContext>[];
    for (final screen in analysis.screenContexts) {
      final source = File(screen.filePath).readAsStringSync();
      final imports = projectImports(
        source,
        filePath: screen.filePath,
        projectPath: projectPath,
        packageName: analysis.projectInfo.packageName,
      );
      contexts.add(PromptContext(
        screenName: screen.name,
        screenId: screen.relativePath,
        importUri: screen.importUri,
        context: render(screen.filePath, source, imports),
        navigationImports: imports,
        nodesVisited: 0,
      ));
    }
    contexts.sort((a, b) => a.screenName.compareTo(b.screenName));
    return contexts;
  }

  static String _fence(String source) => '```dart\n${source.trimRight()}\n```';

  static String _section(String path, String source) =>
      '### ${path.replaceAll(r'\', '/')}\n${_fence(source)}';

  /// The project-local libraries [source] imports, as `package:` URIs. These
  /// are visible in the raw source anyway, so allowing them adds no
  /// information the baseline would not otherwise have.
  static List<String> projectImports(
    String source, {
    required String filePath,
    required String projectPath,
    required String packageName,
  }) {
    final unit = parseString(content: source, throwIfDiagnostics: false).unit;
    final libDir = p.join(projectPath, 'lib');
    final imports = <String>{};

    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      if (uri.startsWith('package:$packageName/')) {
        imports.add(uri);
      } else if (!uri.contains(':')) {
        final target = p.normalize(p.join(p.dirname(filePath), uri));
        if (p.isWithin(libDir, target)) {
          imports.add('package:$packageName/'
              '${p.relative(target, from: libDir).replaceAll(r'\', '/')}');
        }
      }
    }
    return imports.toList()..sort();
  }
}
