import 'package:flutterastest/prompt_optimizer/models/optimize_prompt.dart';

import '../prompt_builder/models/prompt_context.dart';

class PromptOptimizer {
  OptimizedPrompt optimize(PromptContext context) {
    // Future Research Novelty: You can query the PKG here to filter out
    // widgets or state variables that don't have active edges!

    return OptimizedPrompt(
      screenName: context.screenName,
      widgetTree: context.widgetTree,
      state: context.state,
      callbacks: context.callbacks,
      dependencies: context.dependencies,
      navigation: context.navigation,
    );
  }
}
