import 'dart:io';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import 'llm_service.dart';
import 'gemini_llm_service.dart';
// 👇 Fixed the import statement here!
import 'response_parser.dart' as response_parser;

class LlmModule implements PipelineModule {
  final LlmService _llmService;

  LlmModule({LlmService? llmService})
      // 👇 Make sure you paste the key starting with AIza here!
      : _llmService = llmService ??
            GeminiLlmService(
                apiKey:
                    'AQ.Ab8RN6KuG491bEE05WjDbKpSviyyjW3xVFaRvJqNOMtLqsWeBA');

  @override
  PipelineStage get stage => PipelineStage.analysis;

  @override
  Future<void> execute(PipelineContext context) async {
    print('\nGenerating Widget Tests via LLM...');
    print('------------------------------------');

    final promptDir = Directory('output/prompts');
    final outputDir = Directory('generated_tests');

    if (!await promptDir.exists()) {
      throw Exception(
        'Prompts directory output/prompts not found. Run PromptOptimizerModule first.',
      );
    }

    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final parser = ResponseParser();
    final promptFiles = promptDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_prompt.txt'))
        .toList();

    if (promptFiles.isEmpty) {
      print('No prompt files found in output/prompts/');
      return;
    }

    int generatedCount = 0;

    for (final file in promptFiles) {
      final fileName = file.uri.pathSegments.last;
      final screenName = fileName.replaceAll('_prompt.txt', '');

      print('Calling LLM for: $screenName...');

      final promptText = await file.readAsString();

      // 1. Request test code from LLM
      final rawResponse = await _llmService.generateTest(promptText);

      // 2. Parse out clean Dart code
      final cleanCode = parser.extractDartCode(rawResponse);

      // 3. Save as _test.dart file
      final testFile = File('${outputDir.path}/${screenName}_test.dart');
      await testFile.writeAsString(cleanCode);

      generatedCount++;

      // Base delay to spread out the 25 requests and avoid rate limits
      if (generatedCount < promptFiles.length) {
        print('Waiting 10 seconds to respect API rate limits...');
        await Future.delayed(const Duration(seconds: 10));
      }
    }

    print(
      '\nSuccessfully generated and saved $generatedCount test files to ${outputDir.path}/',
    );
  }
}
