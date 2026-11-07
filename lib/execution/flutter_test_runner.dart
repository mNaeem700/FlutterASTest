import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'flutter_command.dart';
import 'json_reporter_parser.dart';
import 'lcov.dart';
import 'models/test_run.dart';

/// Runs one generated test file inside the target project, where its
/// `package:` imports and dependencies resolve.
///
/// The file is copied into `test/flutterastest_tmp/` of the project for the
/// duration of the run and deleted afterwards; nothing else in the project is
/// written except Flutter's own build cache. Coverage goes to [lcovPath]
/// outside the project.
class FlutterTestRunner {
  FlutterTestRunner({
    this.flutter = const FlutterCommand('flutter', source: 'PATH'),
    JsonReporterParser parser = const JsonReporterParser(),
  }) : _parser = parser;

  static const tempDirectoryName = 'flutterastest_tmp';
  static const _createdMarker = '.flutterastest_created';

  final FlutterCommand flutter;
  final JsonReporterParser _parser;

  static Directory tempDirectory(String projectPath) =>
      Directory(p.join(projectPath, 'test', tempDirectoryName));

  /// Removes files left behind by an interrupted earlier run.
  static Future<void> cleanUp(String projectPath) async {
    final dir = tempDirectory(projectPath);
    // On Windows the test process can hold its files for a moment after it
    // exits. A folder left behind is harmless and is removed by the next run.
    for (var attempt = 0; attempt < 10 && await dir.exists(); attempt++) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    if (await dir.exists()) return;
    // Remove test/ only when this tool created it and nothing else is in it.
    final marker = File(p.join(projectPath, 'test', _createdMarker));
    if (await marker.exists()) {
      final entries = await marker.parent.list().toList();
      if (entries.length == 1) await marker.parent.delete(recursive: true);
    }
  }

  static const _preflightTest = '''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('flutterastest preflight', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('ok')));
    expect(find.text('ok'), findsOneWidget);
  });
}
''';

  /// Runs a trivial widget test in the project. Returns null when the
  /// toolchain works, otherwise the reason it does not. Without this check a
  /// broken Flutter SDK or unresolved dependencies would be recorded as
  /// "generated test does not compile" for every screen.
  Future<String?> preflight(String projectPath, {required Duration timeout}) async {
    final lcov = p.join(Directory.systemTemp.path, 'flutterastest_preflight.lcov.info');
    final run = await this.run(
      projectPath: projectPath,
      screenName: '_preflight',
      screenFile: '',
      code: _preflightTest,
      lcovPath: lcov,
      timeout: timeout,
    );
    if (run.allPassed) return null;
    final reason = run.loadErrors.isNotEmpty
        ? run.loadErrors.first
        : run.cases.map((c) => c.message ?? c.name).join('\n');
    final lines = reason.split('\n');
    return lines.take(6).join('\n');
  }

  Future<TestRun> run({
    required String projectPath,
    required String screenName,
    required String screenFile,
    required String code,
    required String lcovPath,
    required Duration timeout,
    bool collectCoverage = true,
  }) async {
    if (code.trim().isEmpty) {
      return const TestRun(
        compiled: false,
        cases: [],
        durationMs: 0,
        loadErrors: ['No test code was generated.'],
      );
    }

    final testRoot = Directory(p.join(projectPath, 'test'));
    final createdTestRoot = !await testRoot.exists();
    final dir = tempDirectory(projectPath);
    await dir.create(recursive: true);
    if (createdTestRoot) {
      await File(p.join(testRoot.path, _createdMarker)).writeAsString('');
    }

    final testFile = File(p.join(dir.path, '${screenName}_test.dart'));
    await testFile.writeAsString(code);
    final lcov = File(lcovPath);
    await lcov.parent.create(recursive: true);
    if (await lcov.exists()) await lcov.delete();

    final stopwatch = Stopwatch()..start();
    try {
      final process = await flutter.start(
        [
          'test',
          p.relative(testFile.path, from: projectPath),
          '--reporter',
          'json',
          '--no-pub',
          if (collectCoverage) ...['--coverage', '--branch-coverage', '--coverage-path', lcov.absolute.path],
        ],
        workingDirectory: projectPath,
      );

      final stdoutText = process.stdout.transform(utf8.decoder).join();
      final stderrText = process.stderr.transform(utf8.decoder).join();

      var timedOut = false;
      await process.exitCode.timeout(timeout, onTimeout: () async {
        timedOut = true;
        await _killTree(process.pid);
        return -1;
      });
      stopwatch.stop();

      final output = '${await stdoutText}\n${await stderrText}';
      final outcome = _parser.parse(output);

      LineCoverage? coverage;
      if (await lcov.exists()) {
        final report = LcovReport.parse(await lcov.readAsString(), projectPath: projectPath);
        coverage = report.coverageOf(screenFile) ?? (outcome.compiled ? LineCoverage.none : null);
      }

      return TestRun(
        compiled: outcome.compiled,
        cases: outcome.cases,
        durationMs: stopwatch.elapsedMilliseconds,
        loadErrors: [
          ...outcome.loadErrors,
          if (timedOut) 'Timed out after ${timeout.inSeconds} s and was killed.',
        ],
        timedOut: timedOut,
        screenCoverage: coverage,
        lcovPath: await lcov.exists() ? lcov.path : null,
      );
    } finally {
      await cleanUp(projectPath);
    }
  }

  /// With `runInShell` the flutter tool runs under a shell, so killing only
  /// the shell would leave the test process running.
  static Future<void> _killTree(int pid) async {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
    } else {
      await Process.run('pkill', ['-TERM', '-P', '$pid']);
      Process.killPid(pid);
    }
  }
}
