class WidgetTreeFormatter {
  String format(String screenName, List<dynamic> hierarchy) {
    final buffer = StringBuffer();
    buffer.writeln('Widget Tree');
    buffer.writeln(screenName);

    final Map<String, List<String>> graph = {};
    for (final edge in hierarchy) {
      try {
        final parent = (edge as dynamic).parent.toString();
        final child = (edge as dynamic).child.toString();
        if (parent != 'null' &&
            child != 'null' &&
            !child.contains('Instance of')) {
          graph.putIfAbsent(parent, () => []).add(child);
        }
      } catch (_) {}
    }

    List<String> children = graph[screenName] ?? [];
    if (children.isEmpty) {
      buffer.writeln(' ├── Scaffold');
      buffer.writeln(' │    └── Body');
      buffer.writeln(' │         └── ... (Dynamic Content)');
      return buffer.toString().trim();
    }

    int childCount = 0;
    for (final child in children) {
      buffer.writeln(' ├── $child');
      childCount++;
      final grandChildren = graph[child] ?? [];
      for (final grandChild in grandChildren) {
        buffer.writeln(' │    ├── $grandChild');
        childCount++;
        if (childCount >= 15) break;
      }
      if (childCount >= 15) {
        buffer.writeln(' │    └── ... (Truncated for LLM Context)');
        break;
      }
    }
    return buffer.toString().trim();
  }
}
