import 'package:meta/meta.dart';

@immutable
class SourceFile {
  const SourceFile({
    required this.path,
    required this.relativePath,
  });

  final String path;

  final String relativePath;
}
