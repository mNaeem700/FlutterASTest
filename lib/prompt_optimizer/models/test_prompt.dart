import 'package:meta/meta.dart';

/// The final prompt sent to the LLM for one screen.
@immutable
class TestPrompt {
  const TestPrompt({
    required this.screenName,
    required this.screenFile,
    required this.text,
  });

  final String screenName;

  /// Screen source file relative to the project root, e.g. `lib/login.dart`.
  final String screenFile;
  final String text;
}
