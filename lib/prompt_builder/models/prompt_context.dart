class PromptContext {
  final String screenName;
  final String widgetTree;
  final String state;
  final String callbacks;
  final String dependencies;
  final String navigation;
  final String prompt;

  PromptContext({
    required this.screenName,
    required this.widgetTree,
    required this.state,
    required this.callbacks,
    required this.dependencies,
    required this.navigation,
    required this.prompt,
  });
}
