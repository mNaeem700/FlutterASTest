import 'package:meta/meta.dart';

@immutable
class CLIOptions {
  final String command;

  final String? projectPath;

  final bool verbose;

  final bool help;

  final bool version;

  const CLIOptions({
    required this.command,
    required this.projectPath,
    required this.verbose,
    required this.help,
    required this.version,
  });
}
