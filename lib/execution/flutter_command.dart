import 'dart:io';

import 'package:path/path.dart' as p;

/// How to invoke Flutter for one target project. FlutterASTest uses whatever
/// the developer's project already uses, and never installs or upgrades an SDK.
class FlutterCommand {
  const FlutterCommand(this.executable, {this.prefix = const [], required this.source});

  final String executable;

  /// Arguments before Flutter's own, e.g. `flutter` for `fvm flutter`.
  final List<String> prefix;

  /// Why this Flutter was chosen, for logs and the reproducibility record.
  final String source;

  /// In order: an explicit override, the project's FVM SDK link, FVM itself
  /// when the project is pinned but the link is missing, then `flutter` on PATH.
  factory FlutterCommand.resolve(String projectPath, {String? override}) {
    if (override != null) return FlutterCommand(override, source: '--flutter option');

    final link = p.join(projectPath, '.fvm', 'flutter_sdk', 'bin',
        Platform.isWindows ? 'flutter.bat' : 'flutter');
    if (File(link).existsSync()) return FlutterCommand(link, source: 'project FVM SDK');

    final pinned = File(p.join(projectPath, '.fvmrc')).existsSync() ||
        File(p.join(projectPath, '.fvm', 'fvm_config.json')).existsSync();
    if (pinned) return const FlutterCommand('fvm', prefix: ['flutter'], source: 'project FVM config');

    return const FlutterCommand('flutter', source: 'PATH');
  }

  Future<Process> start(List<String> arguments, {required String workingDirectory}) =>
      Process.start(executable, [...prefix, ...arguments],
          workingDirectory: workingDirectory, runInShell: true);

  Future<ProcessResult> runIn(List<String> arguments, String workingDirectory) =>
      Process.run(executable, [...prefix, ...arguments],
          workingDirectory: workingDirectory, runInShell: true);

  Future<ProcessResult> run(List<String> arguments) =>
      Process.run(executable, [...prefix, ...arguments], runInShell: true);

  @override
  String toString() => '${[executable, ...prefix].join(' ')} ($source)';
}
