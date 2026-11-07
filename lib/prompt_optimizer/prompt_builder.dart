import 'package:flutterastest/analysis/models/project_info_model.dart';

/// The fixed test-generation prompt. Every experiment mode uses the same
/// task, project facts and rules; only the context section differs, so
/// differences in results come from the context and not from the wording.
class PromptBuilder {
  const PromptBuilder();

  static const templateVersion = '1.1';

  /// A unit test for one class or a file's functions; no Flutter UI involved.
  String buildUnit({
    required ProjectInfoModel project,
    required String targetName,
    required String importUri,
    required List<String> imports,
    required String context,
  }) {
    final mocking = project.mockingLibraries;
    final allowed = [
      'package:flutter_test/flutter_test.dart',
      importUri,
      ...imports.where((uri) => uri != importUri),
      for (final lib in mocking) 'package:$lib/$lib.dart',
    ];
    return '''
You are an expert Dart engineer writing unit tests.

## Task
Write one complete, compilable unit test file for `$targetName` of the Flutter app `${project.packageName}`.

## Rules
1. Reply with exactly one ```dart code block that contains the whole test file, and nothing else.
2. Import only the libraries listed under "Allowed imports". Never invent other imports or placeholder paths.
3. Use `test` and `group` from flutter_test, and call `TestWidgetsFlutterBinding.ensureInitialized()` first if the code uses Flutter services.
4. Test each public method's behaviour: normal input, edge cases and errors. Assert real results.
5. Do not call real network, storage or Firebase services. Mocking libraries available: ${mocking.isEmpty ? 'none, so write small fakes by hand' : mocking.join(', ')}. If something cannot be tested without those services, skip it and explain why in a code comment.
6. Keep tests deterministic: no real waiting.
7. Never hide failures: no try/catch around test steps, and no `if` around assertions. A test that cannot pass honestly must fail.

## Allowed imports
${[for (final uri in allowed) "- `import '$uri';`"].join('\n')}

## Source under test
```dart
$context
```
''';
  }

  /// Ablation A4: no rules, project facts or import list, only the task.
  String buildMinimal({
    required String packageName,
    required String screenName,
    required String contextTitle,
    required String context,
  }) =>
      'Write a Flutter widget test file for the screen `$screenName` of the app '
      '`$packageName`. Reply with one ```dart code block.\n\n## $contextTitle\n$context\n';

  String build({
    required ProjectInfoModel project,
    required String screenName,
    required String? importUri,
    required List<String> navigationImports,
    required String contextTitle,
    required String context,
  }) {
    final mocking = project.mockingLibraries;
    final allowedImports = [
      'package:flutter/material.dart',
      'package:flutter_test/flutter_test.dart',
      if (importUri != null) importUri,
      ...navigationImports.where((uri) => uri != importUri),
      if (project.usesGetX) 'package:get/get.dart',
      for (final lib in mocking) 'package:$lib/$lib.dart',
    ];

    final out = StringBuffer()
      ..writeln('You are an expert Flutter engineer writing widget tests with flutter_test.')
      ..writeln()
      ..writeln('## Task')
      ..writeln('Write one complete, compilable widget test file for the screen '
          '`$screenName` of the Flutter app `${project.packageName}`.')
      ..writeln()
      ..writeln('## Project facts')
      ..writeln('- Package name: `${project.packageName}`')
      ..writeln('- State management: '
          '${project.stateManagement.isEmpty ? 'none detected (setState)' : project.stateManagement.join(', ')}')
      ..writeln('- Uses Firebase: ${project.usesFirebase ? 'yes' : 'no'}')
      ..writeln('- Mocking libraries available: '
          '${mocking.isEmpty ? 'none, so do not import mockito or mocktail; write small fakes by hand if you need them' : mocking.join(', ')}')
      ..writeln()
      ..writeln('## Rules')
      ..writeln('1. Reply with exactly one ```dart code block that contains the whole test file, and nothing else.')
      ..writeln('2. Import only the libraries listed under "Allowed imports". Never invent other imports or placeholder paths.')
      ..writeln('3. Pump the screen inside ${project.usesGetX ? '`GetMaterialApp`' : '`MaterialApp`'} so navigation and theming work.')
      ..writeln('4. Build finders from the texts, icons and keys shown in the context where possible.')
      ..writeln('5. Write one `testWidgets` that checks the screen renders, plus one per user interaction.')
      ..writeln('6. For navigation, call `pumpAndSettle` and assert the destination with `find.byType`.')
      ..writeln('7. Do not call real network, storage or Firebase services. If the screen cannot be built without them, '
          'test only what renders without them and explain why in a code comment.')
      ..writeln('8. Keep tests deterministic: no real waiting; advance timers with `tester.pump(duration)`.')
      ..writeln('9. Never hide failures: no try/catch around test steps, no `tester.takeException()` to ignore errors, and no `if` around finders or assertions. If the screen itself throws, let the test fail so the bug is seen.');
    if (project.usesGetX) {
      out.writeln('10. Register any controller the screen obtains with `Get.find` using `Get.put` before pumping, '
          'and call `Get.reset()` in `tearDown`.');
    }

    out
      ..writeln()
      ..writeln('## Allowed imports')
      ..writeln([for (final uri in allowedImports) "- `import '$uri';`"].join('\n'))
      ..writeln()
      ..writeln('## $contextTitle')
      ..writeln(context);

    return out.toString();
  }
}
