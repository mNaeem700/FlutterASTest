import 'package:flutterastest/prompt_builder/formatter/callback_formatter.dart';
import 'package:flutterastest/prompt_builder/formatter/dependency_formatter.dart';
import 'package:flutterastest/prompt_builder/formatter/navigation_formatter.dart';
import 'package:flutterastest/prompt_builder/formatter/prompt_assembler.dart';
import 'package:flutterastest/prompt_builder/formatter/state_formatter.dart';
import 'package:flutterastest/prompt_builder/formatter/widget_tree_formatter.dart';
// 👇 1. ADDED the missing WidgetTreeFormatter import
// (Notice: prompt_formatter.dart is completely removed from here!)

import '../analysis/analysis_result.dart';
import 'models/prompt_context.dart';

class PromptContextGenerator {
  final WidgetTreeFormatter _treeFormatter = WidgetTreeFormatter();
  final StateFormatter _stateFormatter = StateFormatter();
  final CallbackFormatter _callbackFormatter = CallbackFormatter();
  final DependencyFormatter _dependencyFormatter = DependencyFormatter();
  final NavigationFormatter _navFormatter = NavigationFormatter();
  final PromptAssembler _assembler = PromptAssembler();

  List<PromptContext> generate(AnalysisResult analysisResult) {
    print('\nGenerating Prompt Context...');
    print('----------------------------');

    final List<PromptContext> contexts = [];
    final Set<String> screenNames = {};

    // Extract valid screen names safely
    for (var s in analysisResult.screens) {
      try {
        final name =
            (s as dynamic).name ?? (s as dynamic).className ?? s.toString();
        if (name != "Instance of 'ScreenModel'") {
          screenNames.add(name.toString());
        }
      } catch (_) {
        screenNames.add(s.toString());
      }
    }

    // Build the PromptContext for each screen
    for (final screenName in screenNames) {
      // 1. Dependencies (Crucial for filtering state & callbacks)
      final screenDeps = _dependencyFormatter.extractDependencies(
          screenName, analysisResult.dependencies);

      // 2. Formatting
      final widgetTree =
          _treeFormatter.format(screenName, analysisResult.hierarchy);
      final state = _stateFormatter.format(analysisResult.states, screenDeps);
      final callbacks = _callbackFormatter.format(
          screenName, analysisResult.callbacks, widgetTree, screenDeps);
      final dependencies = _dependencyFormatter.format(screenDeps);
      final navigation = _navFormatter.format(
          screenName, analysisResult.callbacks, widgetTree);

      // 3. Assemble
      final context = _assembler.assemble(
        screenName: screenName,
        widgetTree: widgetTree,
        state: state,
        callbacks: callbacks,
        dependencies: dependencies,
        navigation: navigation,
      );

      contexts.add(context);
    }

    print('\nGenerated context for ${contexts.length} screens.');

    if (contexts.isNotEmpty) {
      print('\nSample Prompt');
      print('========================\n');
      print(contexts.first.prompt);
      print('\n========================\n');
      print('Prompt contexts generated successfully.');
    }

    return contexts;
  }
}
