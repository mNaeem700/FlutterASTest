import 'package:meta/meta.dart';

/// Facts about the analysed Flutter project read from its pubspec.yaml.
@immutable
class ProjectInfoModel {
  const ProjectInfoModel({
    required this.packageName,
    required this.dependencies,
    required this.devDependencies,
    required this.stateManagement,
    required this.usesFirebase,
  });

  final String packageName;
  final List<String> dependencies;
  final List<String> devDependencies;

  /// Detected state-management approaches, e.g. ['GetX'], ['Provider'].
  final List<String> stateManagement;
  final bool usesFirebase;

  /// Mocking libraries a generated test may import without editing pubspec.
  List<String> get mockingLibraries => [
        for (final lib in const ['mocktail', 'mockito'])
          if (devDependencies.contains(lib) || dependencies.contains(lib)) lib,
      ];

  bool get usesGetX => stateManagement.contains('GetX');

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'dependencies': dependencies,
        'devDependencies': devDependencies,
        'stateManagement': stateManagement,
        'usesFirebase': usesFirebase,
      };
}
