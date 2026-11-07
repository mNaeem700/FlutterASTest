import 'models/architecture_health_model.dart';
import 'models/callback_model.dart';
import 'models/project_info_model.dart';
import 'models/screen_context_model.dart';
import 'models/widget_property_model.dart';

class AnalysisResult {
  final int totalFiles;
  final ProjectInfoModel projectInfo;
  final List<dynamic> widgets;
  final List<dynamic> screens;
  final List<dynamic> hierarchy;
  final List<dynamic> navigation;
  final List<dynamic> dependencies;
  final List<dynamic> states;
  final List<CallbackModel> callbacks;
  final List<WidgetPropertyModel> properties;

  /// Per-screen context for test generation, one entry per screen.
  final List<ScreenContextModel> screenContexts;
  final ArchitectureHealthModel? architectureHealth;

  /// Route name → widget class it opens.
  final Map<String, String> routes;

  const AnalysisResult({
    required this.totalFiles,
    required this.projectInfo,
    required this.widgets,
    required this.screens,
    required this.hierarchy,
    required this.navigation,
    required this.dependencies,
    required this.states,
    required this.callbacks,
    required this.properties,
    required this.screenContexts,
    this.architectureHealth,
    this.routes = const {},
  });
}
