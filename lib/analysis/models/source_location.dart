import 'package:meta/meta.dart';

/// A span of source code in the analysed project.
@immutable
class SourceLocation {
  const SourceLocation({
    required this.file,
    required this.offset,
    required this.line,
    required this.endLine,
  });

  /// Path relative to the project root with forward slashes, as lcov reports it.
  final String file;

  /// Character offset of the start, used in canonical PKG node ids.
  final int offset;

  /// 1-based first and last line.
  final int line;
  final int endLine;

  Iterable<int> get lines sync* {
    for (var l = line; l <= endLine; l++) {
      yield l;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SourceLocation &&
      other.file == file &&
      other.offset == offset &&
      other.endLine == endLine;

  @override
  int get hashCode => Object.hash(file, offset, endLine);

  Map<String, dynamic> toJson() => {
        'file': file,
        'offset': offset,
        'line': line,
        'endLine': endLine,
      };

  static SourceLocation? fromJson(Object? json) {
    if (json is! Map) return null;
    return SourceLocation(
      file: json['file'] as String,
      offset: json['offset'] as int,
      line: json['line'] as int,
      endLine: json['endLine'] as int,
    );
  }
}
