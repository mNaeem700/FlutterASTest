abstract final class ExitCodes {
  static const int success = 0;

  static const int invalidArguments = 1;

  static const int configurationError = 2;

  static const int parserError = 3;

  static const int analysisError = 4;

  static const int llmError = 5;

  static const int executionError = 6;

  static const int reflectionError = 7;

  static const int evaluationError = 8;

  static const int unknownError = 255;
}
