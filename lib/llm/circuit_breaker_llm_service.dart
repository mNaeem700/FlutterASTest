import 'llm_service.dart';
import 'models/llm_response.dart';

/// The provider keeps failing, for example because the daily quota is used up.
/// Continuing would only record every remaining screen as a failure.
class LlmUnavailableException implements Exception {
  const LlmUnavailableException(this.failures, this.lastError);

  final int failures;
  final String lastError;

  @override
  String toString() => 'The LLM failed $failures times in a row, so the run stopped. '
      'Last error: $lastError\nFix the cause (often the quota), then run the same command '
      'again with --resume, or restart the batch. Saved replies are not requested again.';
}

/// Doc 12.19.2's circuit breaker: stops after [threshold] consecutive failures.
class CircuitBreakerLlmService implements LlmService {
  CircuitBreakerLlmService(this._inner, {this.threshold = 5});

  final LlmService _inner;
  final int threshold;
  int _failures = 0;

  @override
  String get model => _inner.model;

  @override
  Future<LlmResponse> generate(String prompt) async {
    final response = await _inner.generate(prompt);
    if (response.succeeded) {
      _failures = 0;
      return response;
    }
    if (++_failures >= threshold) {
      throw LlmUnavailableException(_failures, response.error ?? 'empty response');
    }
    return response;
  }
}
