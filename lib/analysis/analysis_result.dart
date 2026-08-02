import 'models/callback_model.dart';
import 'models/architecture_health_model.dart';
import 'models/widget_property_model.dart';

class AnalysisResult {
  final int totalFiles;
  final List<dynamic> widgets;
  final List<dynamic> screens;
  final List<dynamic> hierarchy;
  final List<dynamic> navigation;
  final List<dynamic> dependencies;
  final List<dynamic> states;
  final List<CallbackModel> callbacks;
  final List<WidgetPropertyModel> properties;
  final ArchitectureHealthModel? architectureHealth;

  const AnalysisResult({
    required this.totalFiles,
    required this.widgets,
    required this.screens,
    required this.hierarchy,
    required this.navigation,
    required this.dependencies,
    required this.states,
    required this.callbacks,
    required this.properties,
    this.architectureHealth,
  });
}
