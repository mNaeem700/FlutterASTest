import 'package:flutterastest/prompt_optimizer/models/optimize_prompt.dart';

class PromptBuilder {
  String buildSystemPrompt(OptimizedPrompt prompt) {
    final buffer = StringBuffer();

    buffer.writeln('You are an expert Flutter testing engineer.');
    buffer.writeln('Generate Flutter widget tests for the following screen.\n');

    buffer.writeln('Screen:');
    buffer.writeln(prompt.screenName);
    buffer.writeln();

    buffer.writeln(prompt.widgetTree);
    buffer.writeln();

    buffer.writeln(prompt.state);
    buffer.writeln();

    buffer.writeln(prompt.callbacks);
    buffer.writeln();

    buffer.writeln(prompt.dependencies);
    buffer.writeln();

    buffer.writeln(prompt.navigation);
    buffer.writeln();

    buffer.writeln('Requirements:');
    buffer.writeln('- Generate widget tests.');
    buffer.writeln('- Cover success and failure cases.');
    buffer.writeln('- Use flutter_test.');
    buffer.writeln('- Use mock dependencies.');

    return buffer.toString();
  }
}
