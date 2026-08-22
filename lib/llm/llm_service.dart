import 'dart:async';

abstract class LlmService {
  Future<String> generateTest(String promptText);
}

/// Mock LLM implementation for local testing and pipeline validation.
class MockLlmService implements LlmService {
  @override
  Future<String> generateTest(String promptText) async {
    // Simulate API network latency
    await Future.delayed(const Duration(milliseconds: 800));

    return '''
```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Generated Widget Test', () {
    testWidgets('Should render screen correctly', (WidgetTester tester) async {
      // Setup & Render
      expect(find.byType(Placeholder), findsNothing);
    });
  });
}
''';
  }
}

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
