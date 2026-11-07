import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutterastest/cli/command_parser.dart';
import 'package:flutterastest/experiment/experiment_config.dart';
import 'package:flutterastest/llm/gemini_llm_service.dart';
import 'package:flutterastest/llm/llm_factory.dart';
import 'package:flutterastest/llm/llm_settings.dart';
import 'package:flutterastest/llm/openai_llm_service.dart';
import 'package:flutterastest/mutation/mutation_module.dart';
import 'package:flutterastest/product/product_commands.dart';
import 'package:flutterastest/product/user_config.dart';
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

  group('product', () {
    late Directory home;
    setUp(() => home = Directory.systemTemp.createTempSync('flutterastest_home'));
    tearDown(() => home.deleteSync(recursive: true));

    test('user settings persist and API keys are masked', () {
      final user = UserConfig.load(home: home.path)
        ..['model'] = 'tiny'
        ..setApiKey('gemini', 'abcd1234567890xy');
      final again = UserConfig.load(home: home.path);
      expect(again['model'], 'tiny');
      expect(again.apiKey('gemini'), 'abcd1234567890xy');
      expect(again.describe()['apiKey.gemini'], 'abcd****xy');
      expect(user.describe().values.join(), isNot(contains('1234567890')));
    });

    test('the parser uses saved settings, and a flag overrides them', () {
      final user = UserConfig.load(home: home.path)..['provider'] = 'gemini';
      expect(CommandParser(user: user).parse(['generate']).experiment.provider, 'gemini');
      expect(CommandParser(user: user).parse(['generate', '--provider', 'local']).experiment.provider,
          'local');
      expect(CommandParser(user: user).parse(['generate']).projectPath, p.normalize(p.absolute('.')));
    });

    test('a failed paste is recognised as an invalid key', () {
      expect(apiKeyProblem('\u0016'), contains('right-click'));
      expect(apiKeyProblem('abc def ghi jkl mno pqr stu'), contains('right-click'));
      expect(apiKeyProblem('short'), contains('too short'));
      expect(apiKeyProblem('AQ.Ab8RN6K_abcdefghijklmnop1234'), isNull);
    });

    test('local is the default and refuses non-local addresses', () {
      expect(const ExperimentConfig().provider, 'local');
      expect(isLoopback('http://localhost:11434/v1'), isTrue);
      expect(isLoopback('http://127.0.0.1:1/v1'), isTrue);
      expect(isLoopback('https://api.example.com/v1'), isFalse);
      expect(isLoopback('http://localhost.example.com/v1'), isFalse);
    });

    test('local consent is never needed; a cloud provider needs agreement', () {
      final user = UserConfig.load(home: home.path);
      const consent = CloudConsent();
      consent.ensure('local', accepted: false, user: user);
      consent.ensure('gemini', accepted: true, user: user);
      user.setCloudConsent('openai', true);
      consent.ensure('openai', accepted: false, user: user);
    });

    group('with a local OpenAI-compatible server', () {
      late HttpServer server;
      late String baseUrl;
      Map<String, dynamic>? received;

      setUp(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        baseUrl = 'http://127.0.0.1:${server.port}/v1';
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          if (request.uri.path.endsWith('/models')) {
            request.response.write(jsonEncode({
              'data': [
                {'id': 'tiny'},
              ],
            }));
          } else {
            received = jsonDecode(body) as Map<String, dynamic>;
            request.response.write(jsonEncode({
              'choices': [
                {
                  'message': {'content': 'code'},
                },
              ],
              'usage': {'prompt_tokens': 1, 'completion_tokens': 2},
            }));
          }
          await request.response.close();
        });
      });
      tearDown(() => server.close(force: true));

      test('a real HTTP request carries the prompt and returns the reply', () async {
        final reply = await OpenAiLlmService(apiKey: 'local', model: 'tiny', baseUrl: baseUrl)
            .generate('hello');
        expect(reply.text, 'code');
        expect(reply.outputTokens, 2);
        expect(received!['messages'][0]['content'], 'hello');
      });

      test('doctor finds the model, and reports a missing one', () async {
        expect((await Doctor.checkLocalServer(baseUrl, 'tiny')).ok, isTrue);
        final missing = await Doctor.checkLocalServer(baseUrl, 'other');
        expect(missing.ok, isFalse);
        expect(missing.fix, contains('ollama pull other'));
        expect((await Doctor.checkLocalServer(baseUrl, null)).ok, isFalse);
      });
    });

    test('doctor says so when no server is running', () async {
      final check = await Doctor.checkLocalServer('http://127.0.0.1:9/v1', 'tiny');
      expect(check.ok, isFalse);
      expect(check.fix, contains('Ollama'));
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
      for (final match in RegExp(r"register\('([\w.]+)'").allMatches(code)) {
        expect(commands, contains(match.group(1)), reason: 'registered but not declared');
      }
      expect(manifest['main'], './extension.js');
    });

    test('the listing is complete for the Marketplace', () {
      expect(manifest['publisher'], 'NeemiiDevs');
      expect(File('vscode-extension/${manifest['icon']}').existsSync(), isTrue);
      expect(File('vscode-extension/LICENSE').existsSync(), isTrue);
      expect((manifest['keywords'] as List).length, lessThanOrEqualTo(30));
      expect('${manifest['version']}', '1.1.2');
      for (final step in manifest['contributes']['walkthroughs'][0]['steps'] as List) {
        expect(File('vscode-extension/${step['media']['markdown']}').existsSync(), isTrue);
      }
      expect(code, isNot(contains('sendText')),
          reason: 'a terminal shell may be PowerShell, where a quoted command does not run');
    });

    test('settings the code reads are declared', () {
      final properties = manifest['contributes']['configuration']['properties'] as Map;
      for (final match in RegExp(r"setting\('(\w+)'\)").allMatches(code)) {
        expect(properties.keys, contains('flutterastest.${match.group(1)}'));
      }
    });
  });
}
