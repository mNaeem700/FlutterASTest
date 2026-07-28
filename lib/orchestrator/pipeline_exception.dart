class PipelineException implements Exception {
  const PipelineException(
    this.message,
  );

  final String message;

  @override
  String toString() => message;
}
