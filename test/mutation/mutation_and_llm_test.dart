import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutterastest/cli/command_parser.dart';
import 'package:flutterastest/llm/gemini_llm_service.dart';
import 'package:flutterastest/llm/llm_settings.dart';
import 'package:flutterastest/llm/openai_llm_service.dart';
import 'package:flutterastest/mutation/mutation_module.dart';
import 'package:flutterastest/mutation/mutator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('mutator', () {
    const source = r'''
class Screen {
  bool a = true;
  int f(int x) {
    if (x == 1 && a) return x + 1;
    save();
    return "n" + "m" == "nm" ? 0 : 2;
  }
}
class Other { bool b = x > 1; }
''';

    test('applies each operator inside the chosen classes only', () {
      final mutants = const Mutator().generate(source, classes: {'Screen'});
      final kinds = mutants.map((m) => m.operator).toSet();
      expect(kinds, containsAll(['ROR', 'LOR', 'AOR', 'BCR', 'SDL']));
      expect(mutants.every((m) => m.line <= 8), isTrue, reason: 'class Other is excluded');

      final or = mutants.firstWhere((m) => m.operator == 'LOR').apply(source);
      expect(or, contains('x == 1 || a'));
      final delete = mutants.firstWhere((m) => m.operator == 'SDL').apply(source);
      expect(delete, isNot(contains('save()')));
    });

    test('string concatenation is not mutated into something that cannot compile', () {
      final aor = const Mutator().generate(source).where((m) => m.operator == 'AOR');
      expect(aor.length, 1);
    });

    test('increment and decrement are swapped', () {
      final mutants = const Mutator().generate('class S { void f() { n++; --n; } }');
      expect(mutants.map((m) => m.replacement), ['--', '++']);
    });

    test('mutants still parse', () {
      for (final mutant in const Mutator().generate(source)) {
        expect(parseString(content: mutant.apply(source), throwIfDiagnostics: false).errors,
            isEmpty, reason: mutant.id);
      }
    });

    test('the limit spreads evenly and is deterministic', () {
      final body = List.generate(50, (i) => '    if (x == $i) y();').join('\n');
      final big = 'class S {\n  void f(x) {\n$body\n  }\n}\n';
      final first = const Mutator().generate(big, limit: 10);
      expect(first.length, 10);
      expect(first.map((m) => m.id), const Mutator().generate(big, limit: 10).map((m) => m.id));
      expect(first.last.line, greaterThan(40));
    });
  });

  test('mutation score ignores mutants that did not compile', () {
    const result = MutationResult(killed: 3, survived: ['a'], invalid: 5);
    expect(result.score, 0.75);
    expect(const MutationResult(killed: 0, survived: [], invalid: 2).score, 0);
  });

  test('the working copy leaves out build and platform folders', () {
    final temp = Directory.systemTemp.createTempSync('flutterastest_copy');
    try {
      final from = Directory(p.join(temp.path, 'from'));
      for (final path in ['lib/a.dart', 'build/x', 'android/y', '.dart_tool/package_config.json']) {
        File(p.join(from.path, path)).createSync(recursive: true);
      }
      final to = Directory(p.join(temp.path, 'to'));
      MutationModule.copyProject(from, to);
      expect(File(p.join(to.path, 'lib', 'a.dart')).existsSync(), isTrue);
      expect(File(p.join(to.path, '.dart_tool', 'package_config.json')).existsSync(), isTrue);
      expect(Directory(p.join(to.path, 'build')).existsSync(), isFalse);
      expect(Directory(p.join(to.path, 'android')).existsSync(), isFalse);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  group('LLM requests', () {
    test('Gemini sends nothing extra until settings are given', () {
      expect(GeminiLlmService(apiKey: 'k').requestBody('p').containsKey('generationConfig'), isFalse);
      final body = GeminiLlmService(
        apiKey: 'k',
        settings: const LlmSettings(temperature: 0.2, seed: 7, maxOutputTokens: 4096, topP: 1),
      ).requestBody('p');
      expect(body['generationConfig'],
          {'temperature': 0.2, 'topP': 1.0, 'seed': 7, 'maxOutputTokens': 4096});
    });

    test('OpenAI-compatible request and reply', () {
      final body = OpenAiLlmService(apiKey: 'k', settings: const LlmSettings(temperature: 0.2))
          .requestBody('p');
      expect(body['model'], 'gpt-4.1');
      expect(body['temperature'], 0.2);
      expect(body.containsKey('seed'), isFalse);
      final reply = OpenAiLlmService.parse(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'code'},
            },
          ],
          'usage': {'prompt_tokens': 3, 'completion_tokens': 4},
        }),
        model: 'm',
        latencyMs: 1,
      );
      expect(reply.text, 'code');
      expect(reply.promptTokens, 3);
      expect(OpenAiLlmService.parse('{"choices":[]}', model: 'm', latencyMs: 1).succeeded, isFalse);
    });
  });

  test('CLI reads the new options', () {
    final options = CommandParser().parse([
      'analyze',
      'app',
      '--screen',
      'A',
      '--screen',
      'B',
      '--temperature',
      '0.2',
      '--seed',
      '42',
      '--mutation',
      '--max-mutants',
      '5',
      '--provider',
      'openai',
    ]);
    expect(options.command, 'analyse');
    final config = options.experiment;
    expect(config.screens, {'A', 'B'});
    expect(config.llm.temperature, 0.2);
    expect(config.llm.seed, 42);
    expect(config.mutation, isTrue);
    expect(config.maxMutants, 5);
    expect(config.provider, 'openai');
  });

  group('VS Code extension', () {
    final manifest = jsonDecode(File('vscode-extension/package.json').readAsStringSync())
        as Map<String, dynamic>;
    final code = File('vscode-extension/extension.js').readAsStringSync();

    test('every declared command is registered and activates the extension', () {
      final commands = [
        for (final c in manifest['contributes']['commands'] as List) c['command'] as String,
      ];
      expect(commands, isNotEmpty);
      for (final command in commands) {
        expect(code, contains("'$command'"), reason: command);
      }
      expect(manifest['main'], './extension.js');
    });

    test('settings the code reads are declared', () {
      final properties = manifest['contributes']['configuration']['properties'] as Map;
      for (final match in RegExp(r"setting\('(\w+)'\)").allMatches(code)) {
        expect(properties.keys, contains('flutterastest.${match.group(1)}'));
      }
    });
  });
}
