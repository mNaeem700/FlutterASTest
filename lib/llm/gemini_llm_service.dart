import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'llm_service.dart';
import 'llm_settings.dart';
import 'models/llm_response.dart';

class GeminiLlmService implements LlmService {
  GeminiLlmService({
    required this.apiKey,
    this.model = 'gemini-3.6-flash',
    this.maxAttempts = 4,
    this.retryDelay = const Duration(seconds: 30),
    this.settings = const LlmSettings(),
  });

  final String apiKey;
  final LlmSettings settings;

  @override
  final String model;
  final int maxAttempts;

  /// Wait before retrying, long enough to clear a requests-per-minute block.
  final Duration retryDelay;

  /// Quota, overload and server errors are worth retrying; other 4xx are not.
  static const _retryableStatus = {408, 429, 500, 502, 503, 504};

  Map<String, dynamic> requestBody(String prompt) {
    final generation = {
      if (settings.temperature != null) 'temperature': settings.temperature,
      if (settings.topP != null) 'topP': settings.topP,
      if (settings.seed != null) 'seed': settings.seed,
      if (settings.maxOutputTokens != null) 'maxOutputTokens': settings.maxOutputTokens,
    };
    return {
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      if (generation.isNotEmpty) 'generationConfig': generation,
    };
  }

  @override
  Future<LlmResponse> generate(String prompt) async {
    final stopwatch = Stopwatch()..start();
    var lastError = 'no attempt made';

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final client = HttpClient();
      try {
        final uri = Uri.https(
          'generativelanguage.googleapis.com',
          '/v1beta/models/$model:generateContent',
        );
        final request = await client.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.headers.set('x-goog-api-key', apiKey);
        request.write(jsonEncode(requestBody(prompt)));

        final timeout = settings.requestTimeout ?? const Duration(minutes: 10);
        final response = await request.close().timeout(timeout);
        final body = await response.transform(utf8.decoder).join().timeout(timeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          lastError = 'HTTP ${response.statusCode}: ${_firstLine(body)}';
          if (!_retryableStatus.contains(response.statusCode)) break;
        } else {
          return _parse(body, stopwatch.elapsedMilliseconds);
        }
      } on FormatException catch (e) {
        // A malformed request will fail the same way every time.
        lastError = _firstLine(e.toString());
        break;
      } on Exception catch (e) {
        lastError = _firstLine(e.toString());
      } finally {
        client.close(force: true);
      }

      print('  Gemini call failed (attempt $attempt/$maxAttempts): $lastError');
      if (attempt < maxAttempts) {
        print('  Retrying in ${retryDelay.inSeconds} s...');
        await Future<void>.delayed(retryDelay);
      }
    }

    return LlmResponse.failed(
      model: model,
      latencyMs: stopwatch.elapsedMilliseconds,
      error: lastError,
    );
  }

  LlmResponse _parse(String body, int latencyMs) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final usage = data['usageMetadata'] as Map<String, dynamic>?;
    final promptTokens = usage?['promptTokenCount'] as int?;
    final candidateTokens = usage?['candidatesTokenCount'] as int?;
    // Thinking tokens are billed as output, so they count as generation effort.
    final thoughtTokens = usage?['thoughtsTokenCount'] as int? ?? 0;
    final outputTokens = candidateTokens == null ? null : candidateTokens + thoughtTokens;

    final candidates = data['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isEmpty) {
      final feedback = data['promptFeedback'] as Map<String, dynamic>?;
      return LlmResponse.failed(
        model: model,
        latencyMs: latencyMs,
        error: 'no candidates (blockReason: ${feedback?['blockReason'] ?? 'none'})',
      );
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final parts = (candidate['content'] as Map<String, dynamic>?)?['parts'] as List<dynamic>? ??
        const [];
    final text = parts
        .whereType<Map<String, dynamic>>()
        .where((part) => part['thought'] != true)
        .map((part) => part['text'] as String? ?? '')
        .join();

    if (text.trim().isEmpty) {
      return LlmResponse.failed(
        model: model,
        latencyMs: latencyMs,
        error: 'empty response (finishReason: ${candidate['finishReason']})',
      );
    }

    return LlmResponse(
      text: text,
      model: model,
      latencyMs: latencyMs,
      promptTokens: promptTokens,
      outputTokens: outputTokens,
    );
  }

  static String _firstLine(String text) {
    final line = text.trim().split('\n').first;
    return line.length > 300 ? '${line.substring(0, 297)}...' : line;
  }
}
