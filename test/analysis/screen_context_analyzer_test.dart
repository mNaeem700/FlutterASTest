import 'package:flutterastest/analysis/models/screen_context_model.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

void main() {
  late ScreenContextModel login;
  late ScreenContextModel home;

  setUpAll(() {
    final contexts = screenContexts(loginFixture(), ['LoginScreen', 'HomeScreen']);
    login = contexts.firstWhere((c) => c.name == 'LoginScreen');
    home = contexts.firstWhere((c) => c.name == 'HomeScreen');
  });

  test('screen facts: stateful, import URI and state fields', () {
    expect(login.isStateful, isTrue);
    expect(login.stateClassName, '_LoginScreenState');
    expect(login.importUri, 'package:fixture_app/screens/login_screen.dart');
    expect(login.stateFields.map((f) => f.name), contains('emailController'));
    expect(login.lifecycle.map((h) => h.method), contains('dispose'));
  });

  test('widget tree keeps texts, hint texts and keys', () {
    List<WidgetTreeNode> all(List<WidgetTreeNode> nodes) =>
        [for (final n in nodes) ...[n, ...all(n.children)]];
    final nodes = all(login.tree);

    expect(nodes.first.type, 'Scaffold');
    expect(nodes.any((n) => n.type == 'Text' && n.labels.contains('Sign in')), isTrue);
    expect(nodes.any((n) => n.type == 'TextField' && n.labels.contains('Email')), isTrue);
    expect(nodes.any((n) => n.type == 'ElevatedButton' && n.key == 'login'), isTrue);
  });

  test('a conditional handler is summarised from its non-null branch', () {
    final button = login.interactions.firstWhere((i) => i.widgetType == 'ElevatedButton');
    expect(button.event, 'onPressed');
    expect(button.action.calls, contains('auth.login'));
    expect(button.action.isAsync, isTrue);
    expect(button.action.calls.any((c) => c.contains('?')), isFalse,
        reason: 'raw conditional source must not leak into calls');
  });

  test('controller calls are followed into the controller (delegate resolution)', () {
    final button = login.interactions.firstWhere((i) => i.widgetType == 'ElevatedButton');
    expect(button.action.navigation.map((n) => n.api), contains('Get.offAllNamed'));
  });

  test('closure navigation finds the destination widget', () {
    final skip = login.interactions.firstWhere((i) => i.widgetType == 'TextButton');
    final navigation = skip.action.navigation.single;
    expect(navigation.api, 'Get.to');
    expect(navigation.kind, NavigationKind.push);
    expect(navigation.target, 'HomeScreen');
  });

  test('GetBuilder closure parameter is typed, so members used are attributed', () {
    final auth = login.dependencies.singleWhere((d) => d.type == 'AuthController');
    expect(auth.acquisitions, contains('GetBuilder<AuthController>'));
    expect(auth.members.any((m) => m.signature.contains('login(String email)')), isTrue);
    expect(auth.members.any((m) => m.name == 'isLoading'), isTrue);
    expect(auth.members.any((m) => m.name == 'logOut'), isFalse,
        reason: 'members used only by other screens must not appear');
  });

  test('Get.find dependency of a stateless screen', () {
    final auth = home.dependencies.singleWhere((d) => d.type == 'AuthController');
    expect(auth.acquisitions, contains('Get.find'));
    expect(auth.members.single.name, 'logOut');
    expect(home.interactions.single.widgetType, 'IconButton');
  });
}
