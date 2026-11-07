import 'package:flutterastest/pkg/models/knowledge_graph.dart';
import 'package:flutterastest/pkg/models/pkg_edge.dart';
import 'package:flutterastest/pkg/models/pkg_node.dart';
import 'package:flutterastest/pkg/pkg_builder.dart';
import 'package:flutterastest/prompt_builder/prompt_context_generator.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  late KnowledgeGraph graph;

  setUpAll(() {
    graph = PkgBuilder().build(analysisOf(loginFixture(), ['LoginScreen', 'HomeScreen']));
  });

  test('graph has one node per screen and a shared dependency node', () {
    expect(graph.nodesOfType(NodeType.screen).map((n) => n.label),
        unorderedEquals(['LoginScreen', 'HomeScreen']));
    expect(graph.nodesOfType(NodeType.dependency).map((n) => n.label), ['AuthController']);
    expect(graph.nodesOfType(NodeType.screen).first.id,
        matches(RegExp(r'^fixture_app::lib/screens/\w+\.dart::\w+::\d+$')));
  });

  test('each screen uses only its own members of the shared dependency', () {
    final login = graph.nodesOfType(NodeType.screen).firstWhere((n) => n.label == 'LoginScreen');
    final used = graph.targets(login.id, EdgeType.uses).map((n) => n.label);
    expect(used, containsAll(['login', 'isLoading']));
    expect(used, isNot(contains('logOut')));
  });

  test('screen-to-screen navigation is an edge to the destination screen', () {
    final login = graph.nodesOfType(NodeType.screen).firstWhere((n) => n.label == 'LoginScreen');
    final destinations = graph.targets(login.id, EdgeType.navigatesTo).map((n) => n.label);
    expect(destinations, contains('HomeScreen'));
  });

  test('prompt context is rendered from the graph only', () {
    final contexts = const PromptContextGenerator().generate(graph);
    final login = contexts.firstWhere((c) => c.screenName == 'LoginScreen').context;

    expect(login, contains('### Widget tree returned by build()'));
    expect(login, contains('"Sign in"'));
    expect(login, contains("key: 'login'"));
    expect(login, contains('validator: "Email required"'));
    expect(login, contains('`auth.login`'));
    expect(login, contains('login(String email)'));
    expect(login, isNot(contains('logOut')));
    expect(contexts.firstWhere((c) => c.screenName == 'LoginScreen').navigationImports,
        contains('package:fixture_app/screens/home_screen.dart'));
  });
}
