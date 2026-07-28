import 'dart:io';
import 'package:path/path.dart' as p;

class DartFileFinder {
  const DartFileFinder();

  Future<List<String>> findFiles(String projectPath) async {
    final dir = Directory(projectPath);
    if (!await dir.exists()) {
      return [];
    }

    final dartFiles = <String>[];

    // Project ki directory mein recursive search
    final stream = dir.list(recursive: true, followLinks: false);

    await for (final entity in stream) {
      if (entity is File && entity.path.endsWith('.dart')) {
        // Flutter ke auto-generated folders (build aur .dart_tool) ko ignore karna hai
        if (!entity.path.contains('${p.separator}build${p.separator}') &&
            !entity.path.contains('${p.separator}.dart_tool${p.separator}')) {
          dartFiles.add(entity.path);
        }
      }
    }

    return dartFiles;
  }
}
