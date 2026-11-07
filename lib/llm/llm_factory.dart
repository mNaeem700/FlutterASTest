import 'dart:io';

import '../experiment/experiment_config.dart';
import '../product/user_config.dart';
import 'gemini_llm_service.dart';
import 'llm_service.dart';
import 'openai_llm_service.dart';

/// Where a local model server listens by default (Ollama).
const defaultLocalUrl = 'http://localhost:11434/v1';

String localBaseUrl(UserConfig user) =>
    Platform.environment['FLUTTERASTEST_LOCAL_URL'] ?? user['baseUrl'] ?? defaultLocalUrl;

/// True when [url] is this machine; the local provider's privacy promise
/// depends on it.
bool isLoopback(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host == 'localhost' || host == '::1' || host.startsWith('127.');
}

String _requireKey(String variable, String provider, UserConfig user) {
  final key = Platform.environment[variable]?.trim() ?? user.apiKey(provider) ?? '';
  if (key.isEmpty) {
    throw StateError('No API key for $provider. Run: flutterastest config set-key $provider\n'
        '(or set $variable). The key must never be written into source code.');
  }
  return key;
}

/// The LLM provider a run is configured for. A new provider only needs an
/// [LlmService] and a case here.
LlmService createLlmService(ExperimentConfig config) {
  final user = UserConfig.load();
  switch (config.provider) {
    case 'local':
      final baseUrl = localBaseUrl(user);
      if (!isLoopback(baseUrl)) {
        throw StateError('The local provider only talks to this machine, but the URL is '
            '$baseUrl. Use --provider openai for a remote server.');
      }
      final model = config.model ?? user['model'];
      if (model == null) {
        throw StateError('No local model chosen. Run: flutterastest config set model <name>\n'
            '(see "ollama list"), or pass --model <name>. To check your setup: flutterastest doctor');
      }
      return OpenAiLlmService(apiKey: 'local', model: model, baseUrl: baseUrl, settings: config.llm);
    case 'openai':
      final baseUrl = Platform.environment['OPENAI_BASE_URL'];
      return OpenAiLlmService(
        apiKey: baseUrl != null && isLoopback(baseUrl)
            ? (Platform.environment['OPENAI_API_KEY'] ?? 'local')
            : _requireKey('OPENAI_API_KEY', 'openai', user),
        model: config.model ?? user['model'] ?? 'gpt-4.1',
        baseUrl: baseUrl ?? 'https://api.openai.com/v1',
        settings: config.llm,
      );
    case 'gemini':
      final key = _requireKey('GEMINI_API_KEY', 'gemini', user);
      final model = config.model ?? user['model'];
      return model == null
          ? GeminiLlmService(apiKey: key, settings: config.llm)
          : GeminiLlmService(apiKey: key, model: model, settings: config.llm);
    default:
      throw StateError('Unknown LLM provider "${config.provider}". Use local, gemini or openai.');
  }
}
