import 'dart:io';

import 'package:flutterastest/evaluation/evaluation_module.dart';
import 'package:flutterastest/execution/flutter_command.dart';
import 'package:flutterastest/execution/models/test_run.dart';
import 'package:flutterastest/execution/test_installer.dart';
import 'package:flutterastest/experiment/experiment_config.dart';
import 'package:flutterastest/experiment/models/screen_outcome.dart';
import 'package:flutterastest/llm/models/llm_response.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;

  setUp(() => project = Directory.systemTemp.createTempSync('flutterastest_project'));
  tearDown(() => project.deleteSync(recursive: true));

  group('Flutter detection', () {
    test('uses flutter on PATH for a plain project', () {
      expect(FlutterCommand.resolve(project.path).executable, 'flutter');
    });

    test('uses FVM when the project pins a version', () {
      File(p.join(project.path, '.fvmrc')).writeAsStringSync('{"flutter":"3.35.5"}');
      final command = FlutterCommand.resolve(project.path);
      expect(command.executable, 'fvm');
      expect(command.prefix, ['flutter']);
    });

    test("prefers the project's FVM SDK link", () {
      final name = Platform.isWindows ? 'flutter.bat' : 'flutter';
      File(p.join(project.path, '.fvm', 'flutter_sdk', 'bin', name)).createSync(recursive: true);
      expect(FlutterCommand.resolve(project.path).source, 'project FVM SDK');
    });

    test('an explicit option wins', () {
      File(p.join(project.path, '.fvmrc')).createSync();
      expect(FlutterCommand.resolve(project.path, override: 'x').executable, 'x');
    });
  });

  group('output location', () {
    test('a developer run stays in the project and installs tests', () {
      final config = const ExperimentConfig().resolvedFor('app');
      expect(config.installTests, isTrue);
      expect(config.runDirectory, p.join('app', '.flutterastest', 'runs', 'pkg'));
    });

    test('a research run with --output leaves the project unchanged', () {
      final config = const ExperimentConfig(outputRoot: 'out').resolvedFor('app');
      expect(config.installTests, isFalse);
      expect(config.analysisDirectory, p.join('out', 'analysis'));
    });
  });

  test('the HTML report escapes names and shows the outcome', () {
    const response = LlmResponse(text: 'x', model: 'm', latencyMs: 0);
    final outcome = ScreenOutcome(screenName: 'A<B', screenFile: 'f', prompt: 'p')
      ..attempts.add(Attempt(iteration: 0, generation: response, code: 'c')
        ..run = const TestRun(compiled: false, durationMs: 1, cases: []));
    final html = EvaluationModule.toHtml('pkg', [outcome]);
    expect(html, contains('A&lt;B'));
    expect(html, contains('does not compile'));
  });

  group('test installer', () {
    ScreenOutcome outcome(String name, {required bool passing}) {
      const response = LlmResponse(text: 'x', model: 'm', latencyMs: 0);
      return ScreenOutcome(screenName: name, screenFile: 'f', prompt: 'p')
        ..attempts.add(Attempt(iteration: 0, generation: response, code: 'void main() {}')
          ..run = TestRun(compiled: true, durationMs: 1, cases: [
            TestCaseResult(
                name: 't', status: passing ? TestCaseStatus.passed : TestCaseStatus.failed),
          ]));
    }

    test('installs only passing tests', () {
      final installed = const TestInstaller()
          .install(project.path, [outcome('Good', passing: true), outcome('Bad', passing: false)]);
      expect(installed, ['test/flutterastest/Good_test.dart']);
      final text = File(p.join(project.path, installed.single)).readAsStringSync();
      expect(text, startsWith(TestInstaller.marker));
    });

    test('overwrites its own file but never a file the developer wrote', () {
      const installer = TestInstaller();
      final directory = Directory(p.join(project.path, 'test', 'flutterastest'))
        ..createSync(recursive: true);
      final mine = File(p.join(directory.path, 'A_test.dart'))..writeAsStringSync('// mine');

      final first = installer.install(project.path, [outcome('A', passing: true)]);
      expect(first, ['test/flutterastest/A_generated2_test.dart']);
      expect(mine.readAsStringSync(), '// mine');

      final second = installer.install(project.path, [outcome('A', passing: true)]);
      expect(second, first);
    });
  });
}
