class DependencyFormatter {
  List<String> extractDependencies(
      String screenName, List<dynamic> allDependencies) {
    final List<String> deps = [];
    for (final dep in allDependencies) {
      try {
        final depString = dep.toString();
        if (depString.contains(screenName)) {
          final words =
              depString.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), ' ').split(' ');
          for (final word in words) {
            if (word.contains('Controller') ||
                word.contains('Repo') ||
                word.contains('Service') ||
                word.contains('Client')) {
              deps.add(word);
            }
          }
        }
      } catch (_) {}
    }
    return deps.toSet().toList(); // Deduplicate
  }

  String format(List<String> screenDependencies) {
    final buffer = StringBuffer();
    buffer.writeln('Dependencies\n');

    if (screenDependencies.isEmpty) {
      buffer.writeln('None');
      return buffer.toString().trim();
    }

    for (final dep in screenDependencies) {
      buffer.writeln(dep);
    }
    return buffer.toString().trim();
  }
}
