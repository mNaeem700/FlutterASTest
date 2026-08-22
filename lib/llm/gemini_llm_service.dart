import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'llm_service.dart';

class GeminiLlmService implements LlmService {
  final String apiKey;
  late final GenerativeModel _model;

  GeminiLlmService({required this.apiKey}) {
    _model = GenerativeModel(
      // The model successfully verified in your last run
      model: 'gemini-3.6-flash',
      apiKey: apiKey,
    );
  }

  @override
  Future<String> generateTest(String promptText) async {
    // Increase retries to handle the strict free-tier limits
    int maxRetries = 4;

    for (int i = 0; i < maxRetries; i++) {
      try {
        final content = [Content.text(promptText)];
        final response = await _model.generateContent(content);

        return response.text ?? '';
      } catch (e) {
        print('⚠️ Gemini API Error (Attempt ${i + 1}/$maxRetries):');

        // Print just the first line of the error so your console doesn't get flooded
        final errorMessage = e.toString().split('\n').first;
        print('   $errorMessage');

        if (i == maxRetries - 1) {
          print('❌ Failed to generate test after $maxRetries attempts.');
          return ''; // Give up after max retries
        }

        // Wait 15 seconds to clear the "Requests Per Minute" quota block
        print('⏳ Cooling down for 30 seconds before retrying...');
        await Future.delayed(const Duration(seconds: 30));
      }
    }
    return '';
  }
}
