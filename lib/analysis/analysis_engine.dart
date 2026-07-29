import 'package:flutterastest/parser/models/parser_result.dart';
import 'analysis_result.dart';
import 'analyzers/widget_analyzer.dart';
import 'analyzers/screen_analyzer.dart';
import 'analyzers/hierarchy_analyzer.dart';
import 'analyzers/navigation_analyzer.dart';
import 'analyzers/dependency_analyzer.dart';
import 'analyzers/state_analyzer.dart'; // 1. 👇 ADD IMPORT

class AnalysisEngine {
  final WidgetAnalyzer _widgetAnalyzer;
  final ScreenAnalyzer _screenAnalyzer;
  final HierarchyAnalyzer _hierarchyAnalyzer;
  final NavigationAnalyzer _navigationAnalyzer;
  final DependencyAnalyzer _dependencyAnalyzer;
  final StateAnalyzer _stateAnalyzer; // 2. 👇 DECLARE IT

  const AnalysisEngine({
    WidgetAnalyzer widgetAnalyzer = const WidgetAnalyzer(),
    ScreenAnalyzer screenAnalyzer = const ScreenAnalyzer(),
    HierarchyAnalyzer hierarchyAnalyzer = const HierarchyAnalyzer(),
    NavigationAnalyzer navigationAnalyzer = const NavigationAnalyzer(),
    DependencyAnalyzer dependencyAnalyzer = const DependencyAnalyzer(),
    StateAnalyzer stateAnalyzer = const StateAnalyzer(), // 3. 👇 INITIALIZE IT
  })  : _widgetAnalyzer = widgetAnalyzer,
        _screenAnalyzer = screenAnalyzer,
        _hierarchyAnalyzer = hierarchyAnalyzer,
        _navigationAnalyzer = navigationAnalyzer,
        _dependencyAnalyzer = dependencyAnalyzer,
        _stateAnalyzer = stateAnalyzer;

  AnalysisResult analyse(ParserResult parserResult) {
    final widgets = _widgetAnalyzer.analyse(parserResult);
    final screens = _screenAnalyzer.analyse(widgets);
    final hierarchies = _hierarchyAnalyzer.analyse(parserResult);
    final navigation = _navigationAnalyzer.analyse(parserResult);
    final dependencies = _dependencyAnalyzer.analyse(parserResult, widgets);

    final states = _stateAnalyzer.analyse(parserResult); // 4. 👇 ANALYSE STATES

    return AnalysisResult(
      totalFiles: parserResult.totalFiles,
      widgets: widgets,
      screens: screens,
      hierarchy: hierarchies,
      navigation: navigation,
      dependencies: dependencies,
      states: states, // 5. 👇 ADD THIS MISSING PARAMETER!
    );
  }
}
