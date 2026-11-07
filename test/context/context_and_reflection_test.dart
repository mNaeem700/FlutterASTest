import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:flutterastest/analysis/flutter_ast/route_table.dart';
import 'package:flutterastest/context_builder/context_builder.dart';
import 'package:flutterastest/execution/lcov.dart';
import 'package:flutterastest/execution/models/test_run.dart';
import 'package:flutterastest/execution/structural_coverage.dart';
import 'package:flutterastest/experiment/experiment_config.dart';
import 'package:flutterastest/experiment/models/screen_outcome.dart';
import 'package:flutterastest/llm/models/llm_response.dart';
import 'package:flutterastest/llm/response_validator.dart';
import 'package:flutterastest/pkg/graph_serializer.dart';
import 'package:flutterastest/pkg/graph_validator.dart';
import 'package:flutterastest/pkg/models/knowledge_graph.dart';
import 'package:flutterastest/pkg/models/pkg_edge.dart';
import 'package:flutterastest/pkg/models/pkg_node.dart';
import 'package:flutterastest/pkg/pkg_builder.dart';
import 'package:flutterastest/prompt_builder/prompt_context_generator.dart';
import 'package:flutterastest/reflection/failure_analyzer.dart';
import 'package:flutterastest/reflection/reflection_module.dart';
import 'package:flutterastest/reflection/repair_prompt_builder.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  late KnowledgeGraph graph;
  late PkgNode login;

  setUpAll(() {
    graph = PkgBuilder().build(analysisOf(loginFixture(), ['LoginScreen', 'HomeScreen']));
    login = graph.nodesOfType(NodeType.screen).firstWhere((n) => n.label == 'LoginScreen');
  });

  group('PKG', () {
    test('passes validation and serializes as JSON-LD and GraphML', () {
      expect(const GraphValidator().validate(graph), isEmpty);
      final jsonLd = const GraphSerializer().toJsonLd(graph, packageName: 'fixture_app');
      expect(jsonLd['@context'], isNotNull);
      expect((jsonLd['@graph'] as List).length, graph.nodes.length);
      expect(const GraphSerializer().toGraphMl(graph), contains('<graphml'));
    });

    test('building twice gives identical ids', () {
      final again = PkgBuilder().build(analysisOf(loginFixture(), ['LoginScreen', 'HomeScreen']));
      expect(again.nodes.map((n) => n.id), graph.nodes.map((n) => n.id));
    });
  });

  group('Context Builder', () {
    test('score follows the locked formula and is normalized', () {
      const builder = ContextBuilder();
      final field = graph.targets(login.id, EdgeType.bindsState).first;
      // W = 0, N = 0, S = 1, D = 1/2.
      expect(builder.score(graph, field, 1), closeTo(0.25 + 0.15 / 2, 1e-9));
      expect(builder.score(graph, login, 0), closeTo(0.35 + 0.25 + 0.15, 1e-9));
    });

    test('a depth limit bounds semantic hops but not the UI hierarchy', () {
      final shallow = const ContextBuilder(config: ContextConfiguration(maxTraversalDepth: 0))
          .build(graph, login, estimateTokens: (_) => 0);
      final labels = shallow.selected.map((id) => graph.getNode(id)!);
      expect(labels.any((n) => n.label == 'ElevatedButton'), isTrue);
      expect(labels.any((n) => n.type == NodeType.interaction), isFalse);
      expect(labels.any((n) => n.type == NodeType.dependency), isFalse);
    });

    test('pruning is deterministic and keeps mandatory entities', () {
      ContextPackage build() => const ContextBuilder(config: ContextConfiguration(tokenBudget: 10))
          .build(graph, login, estimateTokens: (draft) => draft.selected.length);
      final first = build(), second = build();
      expect(first.selected, second.selected);
      expect(first.prunedNodes, greaterThan(0));
      expect(first.selected, contains(login.id));
      expect(first.selected.length, lessThanOrEqualTo(10));
    });

    test('A1 removes relationships from the rendered context', () {
      final contexts = const PromptContextGenerator(
        keepDelegated: false,
        config: ContextConfiguration(
            excludedEdges: {EdgeType.dependsOn, EdgeType.uses, EdgeType.navigatesTo}),
      ).generate(graph);
      final text = contexts.firstWhere((c) => c.screenName == 'LoginScreen').context;
      expect(text, isNot(contains('AuthController')));
      expect(text, isNot(contains('HomeScreen')));
      expect(text, contains('"Sign in"'));
    });

    test('A2 keeps everything uncompressed', () {
      final package = const ContextBuilder(config: ContextConfiguration(enabled: false))
          .build(graph, login, estimateTokens: (_) => 1 << 30);
      expect(package.collapsed, isEmpty);
      expect(package.prunedNodes, 0);
    });
  });

  test('response validator rejects truncated code and files without tests', () {
    const validator = ResponseValidator();
    expect(validator.validate("void main() { testWidgets('a', (t) async {}); }"), isEmpty);
    expect(validator.validate('void main() { testWidgets('), isNotEmpty);
    expect(validator.validate('void main() {}').single, contains('no test'));
    expect(validator.validate('  ').single, contains('no Dart code'));
  });

  group('structural coverage', () {
    test('maps line hits onto widgets, interactions and navigation', () {
      final screen = screenContexts(loginFixture(), ['LoginScreen', 'HomeScreen'])
          .firstWhere((s) => s.name == 'LoginScreen');
      final file = screen.relativePath;
      final allLines = {
        for (final w in screen.allWidgets) w.location!.line: 1,
      };
      final report = LcovReport({file: allLines});
      final coverage = const StructuralCoverageAnalyzer().analyse(screen, report);
      expect(coverage.widgets.value, 1);
      expect(coverage.navigation.found, greaterThan(0));

      final none = const StructuralCoverageAnalyzer().analyse(screen, LcovReport({file: {}}));
      expect(none.widgets.hit, 0);
      expect(none.interactions.hit, 0);
      expect(none.uncoveredInteractions, isNotEmpty);
    });

    test('lcov branch data', () {
      final report = LcovReport.parse('SF:lib/a.dart\nBRDA:1,0,0,1\nBRDA:1,0,1,0\nend_of_record\n');
      expect(report.branchesOf('lib/a.dart').hit, 1);
      expect(report.branchesOf('lib/a.dart').found, 2);
    });
  });

  group('reflection', () {
    TestRun failing(String message) => TestRun(compiled: true, durationMs: 1, cases: [
          TestCaseResult(name: 't', status: TestCaseStatus.failed, message: message),
        ]);

    test('failure analysis is deterministic and classifies causes', () {
      const analyzer = FailureAnalyzer();
      expect(analyzer.analyse(failing('Found 0 widgets with text')).primaryCause, 'finderNotFound');
      expect(analyzer.analyse(failing('pumpAndSettle timed out')).primaryCause,
          'pumpAndSettleTimeout');
      const compile = TestRun(
          compiled: false, cases: [], durationMs: 1, loadErrors: ["Undefined name 'X'"]);
      expect(analyzer.analyse(compile).primaryCause, 'undefinedSymbol');
      expect(analyzer.analyse(failing('boom')).signature,
          analyzer.analyse(failing('boom')).signature);
    });

    test('confidence is the share of failures the primary cause explains', () {
      const run = TestRun(compiled: true, durationMs: 1, cases: [
        TestCaseResult(name: 'a', status: TestCaseStatus.failed, message: 'Found 0 widgets'),
        TestCaseResult(name: 'b', status: TestCaseStatus.failed, message: 'Found 0 widgets'),
        TestCaseResult(name: 'c', status: TestCaseStatus.failed, message: 'Expected: 1'),
        TestCaseResult(name: 'd', status: TestCaseStatus.failed, message: 'Expected: 2'),
        TestCaseResult(name: 'e', status: TestCaseStatus.failed, message: 'Expected: 3'),
      ]);
      final analysis = const FailureAnalyzer().analyse(run);
      expect(analysis.primaryCause, 'finderNotFound');
      expect(analysis.confidence, closeTo(0.4, 1e-9));
      expect(analysis.secondaryCauses, ['assertion']);
      expect(analysis.evidence.first, 'Found 0 widgets');
    });

    test('coverage guidance decides whether a passing file is finished', () {
      const passing = TestRun(
        compiled: true,
        durationMs: 1,
        cases: [TestCaseResult(name: 't', status: TestCaseStatus.passed)],
        screenCoverage: LineCoverage(linesFound: 10, linesHit: 5),
      );
      expect(ReflectionModule.goalReached(passing, const ExperimentConfig(reflect: true)), isFalse);
      const covered = TestRun(
        compiled: true,
        durationMs: 1,
        cases: [TestCaseResult(name: 't', status: TestCaseStatus.passed)],
        screenCoverage: LineCoverage(linesFound: 10, linesHit: 10),
        branchCoverage: Ratio(1, 2),
      );
      expect(ReflectionModule.goalReached(covered, const ExperimentConfig(reflect: true)), isFalse,
          reason: 'line target met, branch target of 80% not');
      expect(
          ReflectionModule.goalReached(
              passing, const ExperimentConfig(reflect: true, ablation: Ablation.noCoverageGuidance)),
          isTrue);
    });

    test('the best attempt counts, even when a later repair is worse', () {
      const response = LlmResponse(text: 'x', model: 'm', latencyMs: 0);
      final outcome = ScreenOutcome(screenName: 's', screenFile: 'f', prompt: 'p')
        ..attempts.addAll([
          Attempt(iteration: 0, generation: response, code: 'a')
            ..run = const TestRun(compiled: true, durationMs: 1, cases: [
              TestCaseResult(name: 't', status: TestCaseStatus.passed),
            ]),
          Attempt(iteration: 1, generation: response, code: 'b')
            ..run = const TestRun(compiled: false, durationMs: 1, cases: []),
        ]);
      expect(outcome.best!.iteration, 0);
      expect(outcome.finalRun!.allPassed, isTrue);
      expect(outcome.repairs, 1);
    });

    test('repair prompt carries diagnosis and coverage gaps', () {
      final run = failing('Found 0 widgets').copyWith(
        structural: const StructuralCoverage(
          widgets: Ratio(1, 2),
          interactions: Ratio(0, 1),
          navigation: Ratio(0, 1),
          state: Ratio(0, 0),
          uncoveredInteractions: ['`Button` onTap (lib/a.dart:3)'],
        ),
      );
      final prompt = const RepairPromptBuilder().build(
        originalPrompt: 'P',
        previousCode: 'c',
        run: run,
        iteration: 2,
        analysis: const FailureAnalyzer().analyse(run),
        coverageGuided: true,
      );
      expect(prompt, contains('## Diagnosis'));
      expect(prompt, contains('finderNotFound'));
      expect(prompt, contains('`Button` onTap'));
    });
  });

  group('routes', () {
    const routes = r'''
class Routes { static const login = '/login'; }
final pages = [GetPage(name: Routes.login, page: () => const LoginScreen())];
final go = GoRoute(path: '/home', builder: (c, s) => const HomeScreen());
final table = {'/map': (context) => const HomeScreen(), 'other': 3};
''';

    test('GetX, go_router and route maps are read', () {
      final unit = parseString(content: routes, throwIfDiagnostics: false).unit;
      final table = const RouteTable().build([unit], {'LoginScreen', 'HomeScreen'});
      expect(table, {'Routes.login': 'LoginScreen', '/home': 'HomeScreen', '/map': 'HomeScreen'});
    });

    test('helper methods and constants resolve the GetX way', () {
      const helper = r'''
class RouteHelper {
  static const String signIn = '/sign-in';
  static const String home = '/home';
  static String getSignIn() => signIn;
  static String getHome() { return '$home?x=1'; }
  static String other() => missing;
  static List<GetPage> pages = [
    GetPage(name: signIn, page: () => const LoginScreen()),
    GetPage(name: home, page: () => const HomeScreen()),
  ];
}
''';
      final parsed = parseString(content: helper, throwIfDiagnostics: false).unit;
      final table = const RouteTable().build([parsed], {'LoginScreen', 'HomeScreen'});
      expect(table['RouteHelper.signIn'], 'LoginScreen');
      expect(table['RouteHelper.getSignIn()'], 'LoginScreen');
      expect(table['RouteHelper.getHome()'], 'HomeScreen');
      expect(table['/sign-in'], 'LoginScreen');
      expect(table.containsKey('RouteHelper.other()'), isFalse);
    });

    test('a named navigation links to the screen and keeps the route name', () {
      const source = r'''
class ScreenA extends StatelessWidget {
  Widget build(BuildContext context) {
    return Scaffold(body: TextButton(onPressed: () => Get.toNamed('/b'), child: const Text('Go')));
  }
}
class ScreenB extends StatelessWidget {
  Widget build(BuildContext context) => const Scaffold();
}
final pages = [GetPage(name: '/b', page: () => const ScreenB())];
''';
      final analysis = analysisOf([unit('lib/a.dart', source)], ['ScreenA', 'ScreenB'], routes: {'/b': 'ScreenB'});
      final built = PkgBuilder().build(analysis);
      final a = built.nodesOfType(NodeType.screen).firstWhere((n) => n.label == 'ScreenA');
      final edge = built.outgoing(a.id, EdgeType.navigatesTo).single;
      expect(built.getNode(edge.targetId)!.label, 'ScreenB');
      expect(edge.label, 'Get.toNamed(/b)');
    });
  });

  test('run names keep setups apart', () {
    expect(
        const ExperimentConfig(reflect: true, ablation: Ablation.noCoverageGuidance, label: 'rep2')
            .runName,
        'pkg-reflect-noCoverageGuidance-rep2');
    expect(const ExperimentConfig(mode: ContextMode.file).runName, 'file');
  });
}
