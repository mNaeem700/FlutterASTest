import 'dart:io';

import '../experiment/experiment_config.dart';
import 'gemini_llm_service.dart';
import 'llm_service.dart';
import 'openai_llm_service.dart';

String _requireKey(String variable) {
  final key = Platform.environment[variable]?.trim() ?? '';
  if (key.isEmpty) {
    throw StateError('$variable is not set. Set it in your shell before running '
        'FlutterASTest; the key must never be written into source code.');
  }
  return key;
}

/// The LLM provider a run is configured for. A new provider only needs an
/// [LlmService] and a case here.
LlmService createLlmService(ExperimentConfig config) {
  switch (config.provider) {
    case 'openai':
      final baseUrl = Platform.environment['OPENAI_BASE_URL'];
      return OpenAiLlmService(
        apiKey: baseUrl == null ? _requireKey('OPENAI_API_KEY') : (Platform.environment['OPENAI_API_KEY'] ?? ''),
        model: config.model ?? 'gpt-4.1',
        baseUrl: baseUrl ?? 'https://api.openai.com/v1',
        settings: config.llm,
      );
    case 'gemini':
      final key = _requireKey('GEMINI_API_KEY');
      return config.model == null
          ? GeminiLlmService(apiKey: key, settings: config.llm)
          : GeminiLlmService(apiKey: key, model: config.model!, settings: config.llm);
    default:
      throw StateError('Unknown LLM provider "${config.provider}". Use gemini or openai.');
  }
}
