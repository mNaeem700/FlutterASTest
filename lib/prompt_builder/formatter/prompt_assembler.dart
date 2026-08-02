import '../models/prompt_context.dart';

class PromptAssembler {
  PromptContext assemble({
    required String screenName,
    required String widgetTree,
    required String state,
    required String callbacks,
    required String dependencies,
    required String navigation,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('Screen:');
    buffer.writeln(screenName);
    buffer.writeln();
    buffer.writeln(widgetTree);
    buffer.writeln();
    buffer.writeln(state);
    buffer.writeln();
    buffer.writeln(callbacks);
    buffer.writeln();
    buffer.writeln(dependencies);
    buffer.writeln();
    buffer.writeln(navigation);

    final optimizedPrompt = buffer.toString().trim();

    return PromptContext(
      screenName: screenName,
      widgetTree: widgetTree,
      state: state,
      callbacks: callbacks,
      dependencies: dependencies,
      navigation: navigation,
      prompt: optimizedPrompt, // Stored directly in the object for the LLM
    );
  }
}
