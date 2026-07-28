class CLIException implements Exception {
  final String message;

  final int exitCode;

  const CLIException(
    this.message,
    this.exitCode,
  );

  @override
  String toString() => message;
}
