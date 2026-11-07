import 'package:flutterastest/cli/cli_exception.dart';
import 'package:flutterastest/cli/command_parser.dart';
import 'package:flutterastest/experiment/experiment_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final parser = CommandParser();

  test('defaults: PKG mode, no reflection, absolute project path', () {
    final options = parser.parse(['analyse', 'some/app']);
    expect(options.command, 'analyse');
    expect(options.projectPath, p.normalize(p.absolute('some/app')));
    expect(options.experiment.mode, ContextMode.pkg);
    expect(options.experiment.reflect, isFalse);
    expect(options.experiment.runName, 'pkg');
  });

  test('baseline with reflection', () {
    final options = parser.parse(
        ['analyse', 'app', '--mode', 'baseline', '--reflect', '--max-iterations', '3']);
    expect(options.experiment.mode, ContextMode.baseline);
    expect(options.experiment.reflect, isTrue);
    expect(options.experiment.maxIterations, 3);
    expect(options.experiment.runName, 'baseline-reflect');
  });

  test('invalid values are rejected with a CLI error', () {
    expect(() => parser.parse(['analyse', 'app', '--mode', 'raw']), throwsA(isA<CLIException>()));
    expect(() => parser.parse(['analyse', 'app', '--max-iterations', '0']),
        throwsA(isA<CLIException>()));
  });
}
