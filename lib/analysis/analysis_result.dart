import 'models/widget_model.dart';
import 'models/screen_model.dart';
import 'models/widget_edge.dart';
import 'models/navigation_edge.dart';
import 'models/dependency_edge.dart'; // 👇 Added import
import 'models/state_model.dart'; // 👇 Added import

class AnalysisResult {
  const AnalysisResult({
    required this.totalFiles,
    required this.widgets,
    required this.screens,
    required this.hierarchy,
    required this.navigation,
    required this.dependencies, // 👇 Added this
    required this.states,
  });

  final int totalFiles;
  final List<WidgetModel> widgets;
  final List<ScreenModel> screens;
  final List<WidgetEdge> hierarchy;
  final List<NavigationEdge> navigation;
  final List<DependencyEdge> dependencies; // 👇 Added this
  final List<StateModel> states;
}
