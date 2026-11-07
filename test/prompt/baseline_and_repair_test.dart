import 'package:flutterastest/analysis/models/project_info_model.dart';
import 'package:flutterastest/execution/models/test_run.dart';
import 'package:flutterastest/prompt_builder/baseline_context_generator.dart';
import 'package:flutterastest/prompt_optimizer/prompt_builder.dart';
import 'package:flutterastest/reflection/repair_prompt_builder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  group('baseline', () {
    test('allows exactly the project imports the screen source declares', () {
      final imports = BaselineContextGenerator.projectImports(
        loginScreenSource,
        filePath: p.join(fixtureProject, 'lib', 'screens', 'login_screen.dart'),
        projectPath: fixtureProject,
        packageName: 'fixture_app',
      );
      expect(imports, [
        'package:fixture_app/controllers/auth_controller.dart',
        'package:fixture_app/screens/home_screen.dart',
      ]);
    });

    test('both modes share the template; only the context section differs', () {
      const project = ProjectInfoModel(
        packageName: 'fixture_app',
        dependencies: ['get'],
        devDependencies: [],
        stateManagement: ['GetX'],
        usesFirebase: false,
      );
      String build(String title, String context) => const PromptBuilder().build(
            project: project,
            screenName: 'LoginScreen',
            importUri: 'package:fixture_app/screens/login_screen.dart',
            navigationImports: const [],
            contextTitle: title,
            context: context,
          );
      final pkg = build('Screen context (from the Program Knowledge Graph)', 'TREE');
      final baseline = build('Screen source code', 'SOURCE');

      String head(String prompt) => prompt.substring(0, prompt.lastIndexOf('\n## '));
      expect(head(pkg), head(baseline));
      expect(pkg, contains('GetMaterialApp'));
      expect(pkg, contains("import 'package:get/get.dart';"));
    });
  });

  group('repair prompt', () {
    test('includes the previous code and the compile errors', () {
      const run = TestRun(
        compiled: false,
        cases: [],
        durationMs: 10,
        loadErrors: ["Error: Undefined name 'LoginScren'."],
      );
      final prompt = const RepairPromptBuilder().build(
        originalPrompt: 'ORIGINAL',
        previousCode: 'void main() {}',
        run: run,
        iteration: 1,
      );
      expect(prompt, startsWith('ORIGINAL'));
      expect(prompt, contains('## Previous attempt (iteration 0)'));
      expect(prompt, contains('void main() {}'));
      expect(prompt, contains('LoginScren'));
      expect(prompt, contains('## Repair task'));
    });

    test('lists passing tests and the failure message of failing ones', () {
      const run = TestRun(compiled: true, durationMs: 10, cases: [
        TestCaseResult(name: 'renders', status: TestCaseStatus.passed),
        TestCaseResult(name: 'taps', status: TestCaseStatus.failed, message: 'Found 0 widgets'),
      ]);
      final feedback = RepairPromptBuilder.feedback(run);
      expect(feedback, contains('1 test(s) passed, 1 failed.'));
      expect(feedback, contains('PASSED: renders'));
      expect(feedback, contains('FAILED: taps'));
      expect(feedback, contains('Found 0 widgets'));
      expect(run.allPassed, isFalse);
    });
  });
}
