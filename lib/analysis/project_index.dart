import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'models/project_info_model.dart';
import 'models/source_location.dart';

export 'models/source_location.dart';

/// A parsed Dart file. Kept independent of [ResolvedUnitResult] so analyzers
/// can be unit-tested on source parsed with `parseString`.
class SourceUnit {
  const SourceUnit({required this.path, required this.unit});

  final String path;
  final CompilationUnit unit;
}

/// Project-relative path of each parsed unit, set by [ProjectIndex.build].
final _unitPaths = Expando<String>('unitPath');

/// Where [node] is in the project, or null for nodes of units the index did
/// not build (e.g. fragments parsed on their own).
SourceLocation? locate(AstNode node) {
  final root = node.root;
  if (root is! CompilationUnit) return null;
  final file = _unitPaths[root];
  if (file == null) return null;
  return SourceLocation(
    file: file,
    offset: node.offset,
    line: root.lineInfo.getLocation(node.offset).lineNumber,
    endLine: root.lineInfo.getLocation(node.end).lineNumber,
  );
}

class ClassRef {
  const ClassRef({required this.declaration, required this.path});

  final ClassDeclaration declaration;
  final String path;

  String get name => declaration.name.lexeme;
}

/// Project-wide lookup tables shared by all analyzers.
class ProjectIndex {
  ProjectIndex._({
    required this.projectPath,
    required this.info,
    required this.classes,
    required this.widgetClasses,
    required this.stateClassOf,
    required this.units,
  });

  /// Superclasses that make a class a Flutter widget.
  static const widgetBaseClasses = {
    'StatelessWidget',
    'StatefulWidget',
    'GetView',
    'GetWidget',
    'HookWidget',
    'StatefulHookWidget',
    'ConsumerWidget',
    'ConsumerStatefulWidget',
    'HookConsumerWidget',
  };

  static const stateBaseClasses = {'State', 'ConsumerState'};

  final String projectPath;
  final ProjectInfoModel info;

  /// Every class declared in the project, by simple name.
  final Map<String, List<ClassRef>> classes;

  /// Widget classes (direct subclasses of [widgetBaseClasses]).
  final Map<String, ClassRef> widgetClasses;

  /// Widget class name -> its State class.
  final Map<String, ClassRef> stateClassOf;

  /// Every parsed unit of the project.
  final List<CompilationUnit> units;

  factory ProjectIndex.build(List<SourceUnit> units, {required String projectPath}) {
    final classes = <String, List<ClassRef>>{};
    final widgets = <String, ClassRef>{};
    final states = <String, ClassRef>{};

    for (final source in units) {
      _unitPaths[source.unit] = p.relative(source.path, from: projectPath).replaceAll(r'\', '/');
      for (final declaration in source.unit.declarations) {
        if (declaration is! ClassDeclaration) continue;
        final ref = ClassRef(declaration: declaration, path: source.path);
        classes.putIfAbsent(ref.name, () => []).add(ref);

        final superclass = declaration.extendsClause?.superclass;
        if (superclass == null) continue;
        final superName = superclass.name.lexeme;

        if (widgetBaseClasses.contains(superName)) {
          widgets.putIfAbsent(ref.name, () => ref);
        } else if (stateBaseClasses.contains(superName)) {
          final typeArgs = superclass.typeArguments?.arguments ?? const [];
          if (typeArgs.isNotEmpty && typeArgs.first is NamedType) {
            final widgetName = (typeArgs.first as NamedType).name.lexeme;
            states.putIfAbsent(widgetName, () => ref);
          }
        }
      }
    }

    return ProjectIndex._(
      projectPath: projectPath,
      info: readProjectInfo(projectPath),
      classes: classes,
      widgetClasses: widgets,
      stateClassOf: states,
      units: [for (final source in units) source.unit],
    );
  }

  ClassRef? classNamed(String name) {
    final refs = classes[name];
    return refs == null || refs.isEmpty ? null : refs.first;
  }

  bool isWidget(String name) => widgetClasses.containsKey(name);

  /// `package:<name>/<path>` for files under lib/, otherwise null.
  String? importUriFor(String filePath) {
    final libDir = p.join(projectPath, 'lib');
    if (!p.isWithin(libDir, filePath)) return null;
    final relative = p.relative(filePath, from: libDir).replaceAll(r'\', '/');
    return 'package:${info.packageName}/$relative';
  }

  /// Path relative to the project root with forward slashes (stable IDs).
  String relativePath(String filePath) =>
      p.relative(filePath, from: projectPath).replaceAll(r'\', '/');

  static ProjectInfoModel readProjectInfo(String projectPath) {
    final pubspec = File(p.join(projectPath, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      return ProjectInfoModel(
        packageName: p.basename(projectPath),
        dependencies: const [],
        devDependencies: const [],
        stateManagement: const [],
        usesFirebase: false,
      );
    }

    final yaml = loadYaml(pubspec.readAsStringSync());
    List<String> keysOf(Object? section) =>
        section is YamlMap ? section.keys.map((k) => '$k').toList() : <String>[];

    final deps = keysOf(yaml is YamlMap ? yaml['dependencies'] : null);
    final devDeps = keysOf(yaml is YamlMap ? yaml['dev_dependencies'] : null);
    final all = {...deps, ...devDeps};

    const stateLibraries = {
      'get': 'GetX',
      'provider': 'Provider',
      'flutter_bloc': 'Bloc',
      'bloc': 'Bloc',
      'flutter_riverpod': 'Riverpod',
      'hooks_riverpod': 'Riverpod',
      'riverpod': 'Riverpod',
      'mobx': 'MobX',
      'flutter_mobx': 'MobX',
    };

    return ProjectInfoModel(
      packageName: yaml is YamlMap && yaml['name'] != null
          ? '${yaml['name']}'
          : p.basename(projectPath),
      dependencies: deps,
      devDependencies: devDeps,
      stateManagement: {
        for (final entry in stateLibraries.entries)
          if (deps.contains(entry.key)) entry.value,
      }.toList(),
      usesFirebase: all.any((d) => d.startsWith('firebase') || d == 'cloud_firestore'),
    );
  }
}
