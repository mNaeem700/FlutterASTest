import 'dart:async';

import 'models/llm_response.dart';

abstract class LlmService {
  /// Model identifier recorded with every result.
  String get model;

  /// Sends [prompt] and returns the reply. Never throws for provider errors;
  /// a failed call is returned as [LlmResponse.failed] so one screen cannot
  /// abort the whole experiment.
  Future<LlmResponse> generate(String prompt);
}
