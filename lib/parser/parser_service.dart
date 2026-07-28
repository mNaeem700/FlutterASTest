import 'dart_file_finder.dart';

class ParserService {
  const ParserService();

  // Ab yeh Future<List<String>> return karega jo naye architecture ke mutabiq hai
  Future<List<String>> discoverProject(
    String projectPath,
  ) async {
    // ProjectScanner ko bypass kar ke direct file finder call kar rahe hain
    return await const DartFileFinder().findFiles(projectPath);
  }
}
