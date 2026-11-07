import 'package:meta/meta.dart';

/// Sampling and request settings (Doc 12.19). An unset value is not sent, so
/// the provider's default applies. Doc 12's values are temperature 0.2, top P
/// 1.0, 4096 output tokens and a 120 second timeout.
@immutable
class LlmSettings {
  const LlmSettings({
    this.temperature,
    this.topP,
    this.seed,
    this.maxOutputTokens,
    this.requestTimeout,
  });

  final double? temperature;
  final double? topP;
  final int? seed;
  final int? maxOutputTokens;
  final Duration? requestTimeout;

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'topP': topP,
        'seed': seed,
        'maxOutputTokens': maxOutputTokens,
        'requestTimeoutSeconds': requestTimeout?.inSeconds,
      };
}
