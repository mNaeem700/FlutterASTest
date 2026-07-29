import 'dart:io';
import 'package:path/path.dart' as p;

class DartFileFinder {
  const DartFileFinder();

  Future<List<String>> findFiles(String projectPath) async {
    final dartFiles = <String>[];
    final rootDir = Directory(projectPath);

    if (!await rootDir.exists()) return dartFiles;

    // In folders mein scan nahi karna (Time bachane ke liye)
    final excludedDirs = {
      'build',
      '.dart_tool',
      '.git',
      '.idea',
      'ios',
      'android',
      'web',
      'macos',
      'windows',
      'linux'
    };

    // BFS (Breadth-First Search) approach taake excluded folders pehli fursat mein skip ho jayein
    final directoriesToScan = <Directory>[rootDir];

    while (directoriesToScan.isNotEmpty) {
      final currentDir = directoriesToScan.removeLast();

      try {
        final entities = await currentDir.list(followLinks: false).toList();

        for (final entity in entities) {
          if (entity is Directory) {
            final dirName = p.basename(entity.path);
            // Agar folder excluded list mein NAHI hai, toh hi andar jao
            if (!excludedDirs.contains(dirName) && !dirName.startsWith('.')) {
              directoriesToScan.add(entity);
            }
          } else if (entity is File && entity.path.endsWith('.dart')) {
            // Option: Agar aap generated files (.g.dart, .freezed.dart) ko bhi
            // ignore karna chahte hain toh yahan condition laga sakte hain.
            // Filhal hum sab .dart files le rahe hain.
            dartFiles.add(entity.path);
          }
        }
      } catch (e) {
        // Permission issues ko ignore karein
      }
    }

    return dartFiles;
  }
}
