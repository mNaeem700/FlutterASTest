import 'dart:io';

import 'package:flutterastest/cli/flutterastest_cli.dart';

Future<void> main(
  List<String> arguments,
) async {
  final cli = FlutterASTestCLI();

  final exitCode = await cli.execute(arguments);

  exit(exitCode);
}
