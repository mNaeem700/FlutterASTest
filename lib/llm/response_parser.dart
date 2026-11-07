class ResponseParser {
  /// Extracts the Dart code of the first fenced code block (```dart or a bare
  /// ```), or the whole reply when it contains no fence.
  String extractDartCode(String rawResponse) {
    final fenced = RegExp(r'```[ \t]*(?:dart)?[ \t]*\r?\n(.*?)```', dotAll: true);
    final match = fenced.firstMatch(rawResponse);
    if (match != null) return match.group(1)!.trim();

    // An unterminated fence happens when the reply is cut off.
    final open = RegExp(r'```[ \t]*(?:dart)?[ \t]*\r?\n').firstMatch(rawResponse);
    if (open != null) return rawResponse.substring(open.end).trim();

    return rawResponse.trim();
  }
}
