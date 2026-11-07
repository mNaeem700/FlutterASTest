import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'llm_service.dart';
import 'models/llm_response.dart';

/// Saves every successful reply to disk, so an interrupted run can be repeated
/// without paying for the same LLM calls again. Failed calls are not saved, so
/// they are tried again. Each repetition of an experiment has its own
/// [directory], which keeps repetitions independent samples.
class CachingLlmService implements LlmService {
  CachingLlmService(this._inner, this.directory);

  final LlmService _inner;
  final String directory;

  @override
  String get model => _inner.model;

  @override
  Future<LlmResponse> generate(String prompt) async {
    final key = sha256.convert(utf8.encode('$model\n$prompt')).toString();
    final file = File(p.join(directory, '$key.json'));
    if (file.existsSync()) {
      return LlmResponse.fromCacheJson(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    }

    final response = await _inner.generate(prompt);
    if (response.succeeded) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(response.toCacheJson()));
    }
    return response;
  }
}
