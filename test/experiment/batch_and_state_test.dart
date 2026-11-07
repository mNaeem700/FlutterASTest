import 'dart:io';

import 'package:flutterastest/analysis/models/screen_context_model.dart';
import 'package:flutterastest/evaluation/run_comparison.dart';
import 'package:flutterastest/experiment/batch_runner.dart';
import 'package:flutterastest/experiment/experiment_config.dart';
import 'package:flutterastest/llm/caching_llm_service.dart';
import 'package:flutterastest/llm/llm_service.dart';
import 'package:flutterastest/llm/models/llm_response.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixtures.dart';

class _CountingLlm implements LlmService {
  int calls = 0;
  bool fail = false;

  @override
  String get model => 'm';

  @override
  Future<LlmResponse> generate(String prompt) async {
    calls++;
    return fail
        ? const LlmResponse.failed(model: 'm', latencyMs: 1, error: 'quota')
        : LlmResponse(text: 'reply $calls', model: 'm', latencyMs: 7, promptTokens: 3, outputTokens: 4);
  }
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('flutterastest_batch'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('resume', () {
    test('a saved reply is replayed with its original metrics and no new call', () async {
      final llm = _CountingLlm();
      final first = await CachingLlmService(llm, temp.path).generate('p');
      final second = await CachingLlmService(llm, temp.path).generate('p');
      expect(llm.calls, 1);
      expect(first.fromCache, isFalse);
      expect(second.fromCache, isTrue);
      expect(second.text, first.text);
      expect(second.latencyMs, 7);
      expect(second.promptTokens, 3);
    });

    test('a failed call is not saved, so it is tried again', () async {
      final llm = _CountingLlm()..fail = true;
      final cache = CachingLlmService(llm, temp.path);
      await cache.generate('p');
      llm.fail = false;
      expect((await cache.generate('p')).succeeded, isTrue);
      expect(llm.calls, 2);
    });
  });

  group('batch manifest', () {
    const manifest = '''
output: out
repetitions: 2
projects:
  - apps/one
  - {path: apps/two, flutter: custom}
runs:
  - {mode: baseline}
  - {mode: pkg, reflect: true, ablation: noCoverageGuidance}
''';

    test('expands projects x setups x repetitions into separate folders', () {
      final items = BatchRunner.parse(manifest);
      expect(items.length, 8);
      expect(items.first.id, 'one/baseline-rep1');
      expect(items.first.config.resume, isTrue);
      expect(items.first.config.installTests, isFalse);
      expect(items.first.config.outputRoot, p.normalize(p.absolute('out/one')));
      expect(items.last.id, 'two/pkg-reflect-noCoverageGuidance-rep2');
      expect(items.last.flutter, 'custom');
    });

    test('a run with results is complete; others are not', () {
      final item = BatchRunner.parse('''
output: ${temp.path.replaceAll(r'\', '/')}
projects: [apps/one]
runs: [{mode: pkg}]
''').single;
      expect(BatchRunner.isComplete(item), isFalse);
      File(p.join(item.config.runDirectory, 'results.json')).createSync(recursive: true);
      expect(BatchRunner.isComplete(item), isTrue);
    });

    test('a bad manifest is rejected', () {
      expect(() => BatchRunner.parse('projects: []'), throwsFormatException);
    });
  });

  test('batch comparison keeps equal screen names apart and averages repetitions', () {
    void write(String project, String run, String rows) {
      File(p.join(temp.path, project, 'runs', run, 'results.csv'))
        ..createSync(recursive: true)
        ..writeAsStringSync('screen,all_passed,state_coverage_pct\n$rows');
    }

    write('one', 'pkg-rep1', 'Login,true,\n');
    write('one', 'pkg-rep2', 'Login,false,\n');
    write('two', 'pkg-rep1', 'Login,true,50\n');
    write('two', 'pkg-reflect-rep1', 'Login,true,90\n');

    final rows = RunComparison.mergeBatch(temp.path, 'pkg');
    expect(rows.map((r) => r['screen']), unorderedEquals(['one/Login', 'two/Login']));
    final one = rows.firstWhere((r) => r['screen'] == 'one/Login');
    expect(one['all_passed'], '0.5');
    expect(one['state_coverage_pct'], '');
    expect(rows.firstWhere((r) => r['screen'] == 'two/Login')['state_coverage_pct'], '50.0');
  });

  group('state-management styles', () {
    InteractionModel only(String file, String source, String screen) =>
        screenContexts([unit(file, source)], [screen]).single.interactions.single;

    test('Provider: context.read follows into notifyListeners', () {
      final screen =
          screenContexts([unit('lib/p.dart', providerSource)], ['ProviderScreen']).single;
      final dependency = screen.dependencies.singleWhere((d) => d.type == 'CounterModel');
      expect(dependency.acquisitions, contains('context.read'));
      expect(dependency.members.single.name, 'increment');
      final action = screen.interactions.single.action;
      expect(action.calls, contains('CounterModel.increment'));
      expect(action.stateChanges.single, contains('notifyListeners'));
      expect(action.sites.where((s) => s.kind == SiteKind.stateChange), hasLength(1));
    });

    test('Cubit: BlocProvider.of follows into emit', () {
      final action = only('lib/c.dart', cubitSource, 'CubitScreen').action;
      expect(action.calls, contains('CounterCubit.increment'));
      expect(action.stateChanges.single, contains('emit'));
    });

    test('Riverpod: the screen and its notifier call are extracted', () {
      final action = only('lib/r.dart', riverpodSource, 'RiverpodScreen').action;
      expect(action.calls.single, contains('increment'));
    });

    test('ValueNotifier: assignment to value is a state change', () {
      final action = only('lib/v.dart', valueNotifierSource, 'NotifierScreen').action;
      expect(action.stateChanges, ['.value']);
    });

    test('MobX: a store method follows into runInAction', () {
      final action = only('lib/m.dart', mobxSource, 'MobxScreen').action;
      expect(action.calls, contains('store.increment'));
      expect(action.stateChanges.single, contains('runInAction'));
    });
  });

  test('resume flag default stays off for developer runs', () {
    expect(const ExperimentConfig().resolvedFor('app').resume, isFalse);
  });
}
