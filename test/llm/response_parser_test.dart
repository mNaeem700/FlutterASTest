import 'package:flutterastest/llm/response_parser.dart';
import 'package:test/test.dart';

void main() {
  final parser = ResponseParser();

  test('extracts a ```dart block and ignores surrounding prose', () {
    expect(parser.extractDartCode('Here you go:\n```dart\nvoid main() {}\n```\nDone.'),
        'void main() {}');
  });

  test('accepts a bare fence and CRLF line endings', () {
    expect(parser.extractDartCode('```\r\nvoid main() {}\r\n```'), 'void main() {}');
  });

  test('takes the first block when there are several', () {
    expect(parser.extractDartCode('```dart\nA\n```\n```dart\nB\n```'), 'A');
  });

  test('keeps the code of a reply cut off before the closing fence', () {
    expect(parser.extractDartCode('```dart\nvoid main() {'), 'void main() {');
  });

  test('returns a reply without fences as is', () {
    expect(parser.extractDartCode('  void main() {}  '), 'void main() {}');
  });
}
