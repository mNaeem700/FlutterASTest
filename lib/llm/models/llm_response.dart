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
  });

  const LlmResponse.failed({
    required this.model,
    required this.latencyMs,
    required String this.error,
  })  : text = '',
        promptTokens = null,
        outputTokens = null;

  final String text;
  final String model;
  final int latencyMs;
  final int? promptTokens;
  final int? outputTokens;

  /// Why no usable response was returned, e.g. quota exhausted.
  final String? error;

  bool get succeeded => error == null && text.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'model': model,
        'latencyMs': latencyMs,
        'promptTokens': promptTokens,
        'outputTokens': outputTokens,
        if (error != null) 'error': error,
      };
}
