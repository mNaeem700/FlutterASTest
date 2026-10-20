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
