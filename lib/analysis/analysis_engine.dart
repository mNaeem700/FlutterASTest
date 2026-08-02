import 'package:flutterastest/parser/models/parser_result.dart';
import 'analysis_result.dart';
import 'analyzers/widget_analyzer.dart';
import 'analyzers/screen_analyzer.dart';
import 'analyzers/hierarchy_analyzer.dart';
import 'analyzers/navigation_analyzer.dart';
import 'analyzers/dependency_analyzer.dart';
import 'analyzers/state_analyzer.dart';
import 'analyzers/callback_analyzer.dart';
import 'analyzers/widget_property_analyzer.dart';
import 'analyzers/architecture_health_analyzer.dart';

class AnalysisEngine {
  final WidgetAnalyzer _widgetAnalyzer;
  final ScreenAnalyzer _screenAnalyzer;
  final HierarchyAnalyzer _hierarchyAnalyzer;
  final NavigationAnalyzer _navigationAnalyzer;
  final DependencyAnalyzer _dependencyAnalyzer;
  final StateAnalyzer _stateAnalyzer;
  final CallbackAnalyzer _callbackAnalyzer;
  final WidgetPropertyAnalyzer _propertyAnalyzer;
  final ArchitectureHealthAnalyzer _healthAnalyzer;

  const AnalysisEngine({
    WidgetAnalyzer widgetAnalyzer = const WidgetAnalyzer(),
    ScreenAnalyzer screenAnalyzer = const ScreenAnalyzer(),
    HierarchyAnalyzer hierarchyAnalyzer = const HierarchyAnalyzer(),
    NavigationAnalyzer navigationAnalyzer = const NavigationAnalyzer(),
    DependencyAnalyzer dependencyAnalyzer = const DependencyAnalyzer(),
    StateAnalyzer stateAnalyzer = const StateAnalyzer(),
    CallbackAnalyzer callbackAnalyzer = const CallbackAnalyzer(),
    WidgetPropertyAnalyzer propertyAnalyzer = const WidgetPropertyAnalyzer(),
    ArchitectureHealthAnalyzer healthAnalyzer =
        const ArchitectureHealthAnalyzer(),
  })  : _widgetAnalyzer = widgetAnalyzer,
        _screenAnalyzer = screenAnalyzer,
        _hierarchyAnalyzer = hierarchyAnalyzer,
        _navigationAnalyzer = navigationAnalyzer,
        _dependencyAnalyzer = dependencyAnalyzer,
        _stateAnalyzer = stateAnalyzer,
        _callbackAnalyzer = callbackAnalyzer,
        _propertyAnalyzer = propertyAnalyzer,
        _healthAnalyzer = healthAnalyzer;

  AnalysisResult analyse(ParserResult parserResult, {String? projectPath}) {
    final widgets = _widgetAnalyzer.analyse(parserResult);
    final screens = _screenAnalyzer.analyse(widgets);
    final hierarchies = _hierarchyAnalyzer.analyse(parserResult);
    final navigation = _navigationAnalyzer.analyse(parserResult);
    final dependencies = _dependencyAnalyzer.analyse(parserResult, widgets);
    final states =
        _stateAnalyzer.analyse(parserResult, projectPath: projectPath);
    final callbacks = _callbackAnalyzer.analyse(parserResult);

    // 4. 👇 ANALYSE WIDGET PROPERTIES
    final properties = _propertyAnalyzer.analyse(parserResult);

    final health = _healthAnalyzer.analyse(
      dependencies: dependencies,
      widgets: widgets,
      screens: screens,
      navigation: navigation,
      states: states,
    );

    return AnalysisResult(
      totalFiles: parserResult.totalFiles,
      widgets: widgets,
      screens: screens,
      hierarchy: hierarchies,
      navigation: navigation,
      dependencies: dependencies,
      states: states,
      callbacks: callbacks,
      properties: properties, // 5. 👇 INCLUDE IN RESULT
      architectureHealth: health,
    );
  }
}
