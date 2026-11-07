import 'dart:io';

/// CPU time used so far by this process, for the resource metrics of Doc 16.9.
/// Child `flutter test` processes are not included; their cost shows in test
/// execution time. Null when the operating system does not report it.
Future<Duration?> processCpuTime() async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[int64](Get-Process -Id $pid).TotalProcessorTime.TotalMilliseconds',
      ]);
      final ms = int.tryParse('${result.stdout}'.trim());
      return ms == null ? null : Duration(milliseconds: ms);
    }
    final result = await Process.run('ps', ['-o', 'cputime=', '-p', '$pid']);
    return parseCpuTime('${result.stdout}');
  } on ProcessException {
    return null;
  }
}

/// Parses `ps` output: `[dd-]hh:mm:ss`, or `mm:ss.ff` on macOS.
Duration? parseCpuTime(String text) {
  final match = RegExp(r'^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)(?:\.(\d+))?$').firstMatch(text.trim());
  if (match == null) return null;
  int part(int group) => int.parse(match.group(group) ?? '0');
  return Duration(days: part(1), hours: part(2), minutes: part(3), seconds: part(4));
}

/// Share of the machine's total CPU capacity used over [wall], in percent.
double cpuPercent(Duration cpu, Duration wall, int cores) => wall.inMilliseconds == 0 || cores == 0
    ? 0
    : cpu.inMilliseconds / (wall.inMilliseconds * cores) * 100;
