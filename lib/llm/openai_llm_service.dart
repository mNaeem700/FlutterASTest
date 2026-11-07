import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'llm_service.dart';
import 'llm_settings.dart';
import 'models/llm_response.dart';

/// Any OpenAI-compatible chat completions API (Doc 5.3), including local
/// servers such as Ollama through [baseUrl].
class OpenAiLlmService implements LlmService {
  OpenAiLlmService({
    required this.apiKey,
    this.model = 'gpt-4.1',
    this.baseUrl = 'https://api.openai.com/v1',
    this.settings = const LlmSettings(),
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
  });

  final String apiKey;

  @override
  final String model;
  final String baseUrl;
  final LlmSettings settings;
  final int maxAttempts;

  /// Delay before the first retry; it doubles each time (Doc 12.23).
  final Duration retryDelay;

  static const _retryableStatus = {408, 429, 500, 502, 503, 504};

  Map<String, dynamic> requestBody(String prompt) => {
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        if (settings.temperature != null) 'temperature': settings.temperature,
        if (settings.topP != null) 'top_p': settings.topP,
        if (settings.seed != null) 'seed': settings.seed,
        if (settings.maxOutputTokens != null) 'max_tokens': settings.maxOutputTokens,
      };

  @override
  Future<LlmResponse> generate(String prompt) async {
    final stopwatch = Stopwatch()..start();
    final timeout = settings.requestTimeout ?? const Duration(minutes: 10);
    var lastError = 'no attempt made';

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final client = HttpClient();
      try {
        final request = await client.postUrl(Uri.parse('$baseUrl/chat/completions'));
        request.headers.contentType = ContentType.json;
        request.headers.set('authorization', 'Bearer $apiKey');
        request.write(jsonEncode(requestBody(prompt)));
        final response = await request.close().timeout(timeout);
        final body = await response.transform(utf8.decoder).join().timeout(timeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return parse(body, model: model, latencyMs: stopwatch.elapsedMilliseconds);
        }
        lastError = 'HTTP ${response.statusCode}: ${body.split('\n').first}';
        if (!_retryableStatus.contains(response.statusCode)) break;
      } on Exception catch (e) {
        lastError = e.toString().split('\n').first;
      } finally {
        client.close(force: true);
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(retryDelay * (1 << (attempt - 1)));
      }
    }
    return LlmResponse.failed(
        model: model, latencyMs: stopwatch.elapsedMilliseconds, error: lastError);
  }

  static LlmResponse parse(String body, {required String model, required int latencyMs}) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>? ?? const [];
    final message = choices.isEmpty
        ? null
        : (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    final text = message?['content'] as String? ?? '';
    if (text.trim().isEmpty) {
      return LlmResponse.failed(model: model, latencyMs: latencyMs, error: 'empty response');
    }
    final usage = data['usage'] as Map<String, dynamic>?;
    return LlmResponse(
      text: text,
      model: model,
      latencyMs: latencyMs,
      promptTokens: usage?['prompt_tokens'] as int?,
      outputTokens: usage?['completion_tokens'] as int?,
    );
  }
}
