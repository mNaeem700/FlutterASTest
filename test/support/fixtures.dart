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

AnalysisResult analysisOf(List<SourceUnit> units, List<String> screens,
    {Map<String, String> routes = const {}}) {
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
    routes: routes,
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
          TextFormField(
            decoration: const InputDecoration(hintText: 'Email'),
            validator: (v) => v == null || v.isEmpty ? 'Email required' : null,
          ),
          TextFormField(validator: Validators.password),
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

/// The same counter screen in the other supported state-management styles.
const providerSource = r'''
class CounterModel extends ChangeNotifier {
  int count = 0;
  void increment() {
    count++;
    notifyListeners();
  }
}
class ProviderScreen extends StatelessWidget {
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () => context.read<CounterModel>().increment(),
        child: const Text('Add'),
      ),
    );
  }
}
''';

const cubitSource = r'''
class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
}
class CubitScreen extends StatelessWidget {
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<CounterCubit, int>(builder: (context, count) {
        return TextButton(
          onPressed: () => BlocProvider.of<CounterCubit>(context).increment(),
          child: Text('$count'),
        );
      }),
    );
  }
}
''';

const riverpodSource = r'''
class CounterNotifier extends StateNotifier<int> {
  CounterNotifier() : super(0);
  void increment() {
    state = state + 1;
  }
}
class RiverpodScreen extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: TextButton(
        onPressed: () => ref.read(counterProvider.notifier).increment(),
        child: const Text('Add'),
      ),
    );
  }
}
''';

const valueNotifierSource = r'''
class NotifierScreen extends StatefulWidget {
  State<NotifierScreen> createState() => _NotifierScreenState();
}
class _NotifierScreenState extends State<NotifierScreen> {
  final counter = ValueNotifier<int>(0);
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(
        onPressed: () { counter.value = counter.value + 1; },
        child: const Text('Add'),
      ),
    );
  }
}
''';

const mobxSource = r'''
class CounterStore {
  int count = 0;
  void increment() {
    runInAction(() => count++);
  }
}
class MobxScreen extends StatelessWidget {
  final CounterStore store = CounterStore();
  Widget build(BuildContext context) {
    return Scaffold(
      body: TextButton(onPressed: () => store.increment(), child: const Text('Add')),
    );
  }
}
''';

const blocSource = r'''
abstract class AuthEvent {}
class LoginPressed extends AuthEvent {}
class LogoutPressed extends AuthEvent {}
class ResetPressed extends AuthEvent {}
class AuthBloc extends Bloc<AuthEvent, int> {
  AuthBloc() : super(0) {
    on<LoginPressed>((event, emit) {
      emit(1);
      Get.toNamed('/home');
    });
    on<LogoutPressed>(_onLogout);
  }
  void _onLogout(LogoutPressed event, Emitter<int> emit) {
    emit(0);
  }
}
class BlocScreen extends StatelessWidget {
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        TextButton(
          onPressed: () => context.read<AuthBloc>().add(LoginPressed()),
          child: const Text('In'),
        ),
        TextButton(
          onPressed: () => BlocProvider.of<AuthBloc>(context).add(LogoutPressed()),
          child: const Text('Out'),
        ),
        TextButton(
          onPressed: () => context.read<AuthBloc>().add(ResetPressed()),
          child: const Text('Reset'),
        ),
      ]),
    );
  }
}
''';

const getWidgetSource = r'''
import 'package:fixture_app/controllers/home_controller.dart';
class HomeScreen2 extends GetWidget<HomeController> {
  Widget build(BuildContext context) {
    return Scaffold(body: TextButton(onPressed: () => controller.load(), child: const Text('Load')));
  }
}
''';

const homeControllerSource = r'''
class HomeController extends GetxController {
  HomeController(this.api);
  final Api api;
  void load() {}
}
int add(int a, int b) => a + b;
''';

List<SourceUnit> loginFixture() => [
      unit('lib/screens/login_screen.dart', loginScreenSource),
      unit('lib/screens/home_screen.dart', homeScreenSource),
      unit('lib/controllers/auth_controller.dart', authControllerSource),
    ];
