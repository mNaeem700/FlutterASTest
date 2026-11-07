import 'package:analyzer/dart/ast/ast.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../prompt_builder/baseline_context_generator.dart';
import '../project_index.dart';

/// Code that unit tests can target: one class, or a file's top-level functions.
@immutable
class UnitTarget {
  const UnitTarget({
    required this.name,
    required this.relativePath,
    required this.importUri,
    required this.source,
    required this.imports,
  });

  final String name;
  final String relativePath;
  final String importUri;
  final String source;

  /// Project libraries the target's file imports, as `package:` URIs.
  final List<String> imports;

  Map<String, dynamic> toJson() => {'name': name, 'filePath': relativePath};
}

/// Finds classes and functions with logic to test: controllers, services,
/// models and helpers. Widgets are left to widget tests.
class UnitTargetAnalyzer {
  const UnitTargetAnalyzer();

  static const _stateBases = {'State', 'ConsumerState'};

  List<UnitTarget> analyse(ProjectIndex index) {
    final targets = <UnitTarget>[];
    final names = <String>{};

    for (final unit in index.units) {
      final location = locate(unit);
      if (location == null || !_isAppCode(location.file)) continue;
      final uri = index.importUriFor(p.join(index.projectPath, location.file));
      if (uri == null) continue;
      final imports = BaselineContextGenerator.projectImports(
        unit.toSource(),
        filePath: p.join(index.projectPath, location.file),
        projectPath: index.projectPath,
        packageName: index.info.packageName,
      );

      void add(String name, String source) {
        if (names.add(name)) {
          targets.add(UnitTarget(
            name: name,
            relativePath: location.file,
            importUri: uri,
            source: source,
            imports: imports,
          ));
        }
      }

      for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
        final name = declaration.name.lexeme;
        final base = declaration.extendsClause?.superclass.name.lexeme;
        if (name.startsWith('_') || index.isWidget(name) || _stateBases.contains(base)) continue;
        if (_hasLogic(declaration)) add(name, declaration.toSource());
      }

      final functions = [
        for (final function in unit.declarations.whereType<FunctionDeclaration>())
          if (!function.name.lexeme.startsWith('_') && function.name.lexeme != 'main') function,
      ];
      if (functions.isNotEmpty) {
        add('${p.basenameWithoutExtension(location.file)}_functions',
            functions.map((f) => f.toSource()).join('\n\n'));
      }
    }
    targets.sort((a, b) => a.name.compareTo(b.name));
    return targets;
  }

  static bool _isAppCode(String file) =>
      file.startsWith('lib/') &&
      !file.endsWith('.g.dart') &&
      !file.endsWith('.freezed.dart') &&
      !file.endsWith('.mocks.dart');

  static bool _hasLogic(ClassDeclaration declaration) => declaration.members.any((member) =>
      member is MethodDeclaration && !member.isAbstract && member.body is! EmptyFunctionBody);
}
