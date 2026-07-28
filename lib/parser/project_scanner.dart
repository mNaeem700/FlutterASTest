import 'dart:io';

import 'parser_exception.dart';

class ProjectScanner {
  const ProjectScanner();

  Directory scan(String projectPath) {
    final directory = Directory(projectPath);

    if (!directory.existsSync()) {
      throw ParserException(
        'Flutter project does not exist.',
      );
    }

    final pubspec = File(
      '${directory.path}${Platform.pathSeparator}pubspec.yaml',
    );

    if (!pubspec.existsSync()) {
      throw ParserException(
        'pubspec.yaml not found.',
      );
    }

    return directory;
  }
}
