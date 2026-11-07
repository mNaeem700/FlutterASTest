import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutterastest/analysis/analysis_result.dart';
import 'package:flutterastest/analysis/analyzers/screen_context_analyzer.dart';
import 'package:flutterastest/analysis/models/screen_context_model.dart';
import 'package:flutterastest/analysis/models/screen_model.dart';
import 'package:flutterastest/analysis/project_index.dart';
import 'package:path/path.dart' as p;

/// A project that does not exist on disk; analyzers only need the parsed
/// units, and the package name falls back to the folder name.
final fixtureProject = p.absolute('fixture_app');

SourceUnit unit(String relativePath, String source) => SourceUnit(
      path: p.join(fixtureProject, relativePath),
      unit: parseString(content: source, throwIfDiagnostics: false).unit,
    );

ProjectIndex indexOf(List<SourceUnit> units) =>
    ProjectIndex.build(units, projectPath: fixtureProject);

/// Screen contexts of [screens] (class names) in [units].
List<ScreenContextModel> screenContexts(List<SourceUnit> units, List<String> screens) {
  final index = indexOf(units);
  return const ScreenContextAnalyzer().analyse(index, [
    for (final name in screens)
      ScreenModel(
        name: name,
        filePath: index.widgetClasses[name]!.path,
        widgetType: index.stateClassOf.containsKey(name) ? WidgetType.stateful : WidgetType.stateless,
      ),
  ]);
}

AnalysisResult analysisOf(List<SourceUnit> units, List<String> screens) {
  final index = indexOf(units);
  return AnalysisResult(
    totalFiles: units.length,
    projectInfo: index.info,
    widgets: const [],
    screens: const [],
    hierarchy: const [],
    navigation: const [],
    dependencies: const [],
    states: const [],
    callbacks: const [],
    properties: const [],
    screenContexts: screenContexts(units, screens),
  );
}

/// A GetX login screen whose controller comes from a GetBuilder closure.
const loginScreenSource = r'''
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: GetBuilder<AuthController>(builder: (auth) {
        return Column(children: [
          TextField(decoration: const InputDecoration(hintText: 'Email')),
          ElevatedButton(
            key: const Key('login'),
            onPressed: auth.isLoading.value ? null : () async {
              await auth.login(emailController.text);
            },
            child: const Text('Login'),
          ),
          TextButton(
            onPressed: () => Get.to(() => const HomeScreen()),
            child: const Text('Skip'),
          ),
        ]);
      }),
    );
  }
}
''';

const authControllerSource = r'''
import 'package:get/get.dart';

class AuthController extends GetxController {
  final isLoading = false.obs;
  Future<void> login(String email) async {
    isLoading.value = true;
    Get.offAllNamed('/home');
  }
  Future<void> logOut() async {}
  void loadProfile() {}
}
''';

const homeScreenSource = r'''
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Scaffold(
      body: IconButton(icon: const Icon(Icons.logout), onPressed: () => auth.logOut()),
    );
  }
}
''';

List<SourceUnit> loginFixture() => [
      unit('lib/screens/login_screen.dart', loginScreenSource),
      unit('lib/screens/home_screen.dart', homeScreenSource),
      unit('lib/controllers/auth_controller.dart', authControllerSource),
    ];
