/// LLM-ready context for one screen, rendered from the PKG.
class PromptContext {
  const PromptContext({
    required this.screenName,
    required this.screenId,
    required this.importUri,
    required this.context,
    required this.navigationImports,
    required this.nodesVisited,
    this.metrics = const {},
  });

  final String screenName;

  /// PKG node id of the screen.
  final String screenId;
  final String? importUri;

  /// The rendered context section (markdown).
  final String context;

  /// Import URIs of screens this screen navigates to, so tests can find them.
  final List<String> navigationImports;

  /// Number of PKG nodes that contributed to [context].
  final int nodesVisited;

  /// Context Builder metrics (Doc 10.23).
  final Map<String, dynamic> metrics;
}
