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

/// Why [key] cannot be a real API key, or null if it can. Pasting with Ctrl+V
/// into some Windows prompts stores the control character instead of the key.
String? apiKeyProblem(String key) {
  if (key.contains(RegExp(r'[\x00-\x20\x7f]'))) {
    return 'it contains control characters or spaces. The paste probably did not work; '
        'in a Windows terminal, paste with right-click instead of Ctrl+V';
  }
  if (key.length < 20) return 'it is too short (${key.length} characters)';
  return null;
}

String _requireKey(String variable, String provider, UserConfig user) {
  final fromEnv = Platform.environment[variable]?.trim() ?? '';
  final key = fromEnv.isNotEmpty ? fromEnv : (user.apiKey(provider) ?? '');
  if (key.isEmpty) {
    throw StateError('No API key for $provider. Run: flutterastest config set-key $provider\n'
        '(or set $variable). The key must never be written into source code.');
  }
  final problem = apiKeyProblem(key);
  if (problem != null) {
    throw StateError('The $provider API key from '
        '${fromEnv.isNotEmpty ? variable : 'your saved settings'} is not valid: $problem.');
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
