class ResponseParser {
  /// Extracts pure Dart code enclosed within ```dart ... ``` markdown blocks.
  String extractDartCode(String rawResponse) {
    final regex = RegExp(r'```dart\s*\n?(.*?)\n?```', dotAll: true);
    final match = regex.firstMatch(rawResponse);

    if (match != null && match.groupCount >= 1) {
      return match.group(1)!.trim();
    }

    // Fallback: If no markdown code block is found, return trimmed string
    return rawResponse.trim();
  }
}
