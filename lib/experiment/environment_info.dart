import 'dart:convert';
import 'dart:io';

/// The reproducibility record of Doc 16.13: tool and target commits, SDK
/// versions, operating system, CPU and RAM.
class EnvironmentInfo {
  const EnvironmentInfo();

  Future<Map<String, dynamic>> collect({required String projectPath}) async {
    final flutter = await _run('flutter', ['--version', '--machine']);
    Map<String, dynamic>? versions;
    if (flutter != null) {
      final start = flutter.indexOf('{');
      if (start >= 0) {
        try {
          versions = jsonDecode(flutter.substring(start)) as Map<String, dynamic>;
        } on FormatException {
          versions = null;
        }
      }
    }
    return {
      'toolCommit': await _run('git', ['rev-parse', 'HEAD']),
      'toolHasUncommittedChanges': (await _run('git', ['status', '--porcelain']))?.isNotEmpty,
      'targetCommit': await _run('git', ['-C', projectPath, 'rev-parse', 'HEAD']),
      'flutterVersion': versions?['frameworkVersion'],
      'flutterRevision': versions?['frameworkRevision'],
      'dartVersion': versions?['dartSdkVersion'],
      'hostDartVersion': Platform.version,
      'operatingSystem': Platform.operatingSystemVersion,
      'cpu': Platform.environment['PROCESSOR_IDENTIFIER'] ?? await _linuxCpu(),
      'cpuCores': Platform.numberOfProcessors,
      'ramBytes': await _ramBytes(),
    };
  }

  static Future<String?> _run(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments, runInShell: true);
      return result.exitCode == 0 ? (result.stdout as String).trim() : null;
    } on ProcessException {
      return null;
    }
  }

  static Future<String?> _linuxCpu() async {
    final file = File('/proc/cpuinfo');
    if (!file.existsSync()) return null;
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('model name')) return line.split(':').last.trim();
    }
    return null;
  }

  static Future<int?> _ramBytes() async {
    if (Platform.isWindows) {
      final output = await _run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
      ]);
      return output == null ? null : int.tryParse(output);
    }
    final file = File('/proc/meminfo');
    if (!file.existsSync()) return null;
    final match = RegExp(r'MemTotal:\s+(\d+) kB').firstMatch(file.readAsStringSync());
    return match == null ? null : int.parse(match.group(1)!) * 1024;
  }
}
