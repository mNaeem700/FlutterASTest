import 'package:meta/meta.dart';

/// One LLM call. Token counts are the ones the provider reports, not
/// estimates; they are null when the provider did not report them.
@immutable
class LlmResponse {
  const LlmResponse({
    required this.text,
    required this.model,
    required this.latencyMs,
    this.promptTokens,
    this.outputTokens,
    this.error,
    this.fromCache = false,
  });

  const LlmResponse.failed({
    required this.model,
    required this.latencyMs,
    required String this.error,
  })  : text = '',
        promptTokens = null,
        outputTokens = null,
        fromCache = false;

  final String text;
  final String model;
  final int latencyMs;
  final int? promptTokens;
  final int? outputTokens;

  /// Why no usable response was returned, e.g. quota exhausted.
  final String? error;

  /// Replayed from disk, so no provider call was made now.
  final bool fromCache;

  factory LlmResponse.fromCacheJson(Map<String, dynamic> json) => LlmResponse(
        text: json['text'] as String,
        model: json['model'] as String,
        latencyMs: json['latencyMs'] as int,
        promptTokens: json['promptTokens'] as int?,
        outputTokens: json['outputTokens'] as int?,
        fromCache: true,
      );

  Map<String, dynamic> toCacheJson() => {
        'text': text,
        'model': model,
        'latencyMs': latencyMs,
        'promptTokens': promptTokens,
        'outputTokens': outputTokens,
      };

  bool get succeeded => error == null && text.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'model': model,
        'latencyMs': latencyMs,
        'promptTokens': promptTokens,
        'outputTokens': outputTokens,
        if (error != null) 'error': error,
      };
}
