import 'package:flutterastest/parser/models/parser_result.dart';

import 'analysis_result.dart';
import 'analyzers/unit_target_analyzer.dart';
import 'flutter_ast/route_table.dart';
import 'analyzers/architecture_health_analyzer.dart';
import 'analyzers/callback_analyzer.dart';
import 'analyzers/dependency_analyzer.dart';
import 'analyzers/hierarchy_analyzer.dart';
import 'analyzers/navigation_analyzer.dart';
import 'analyzers/screen_analyzer.dart';
import 'analyzers/screen_context_analyzer.dart';
import 'analyzers/state_analyzer.dart';
import 'analyzers/widget_analyzer.dart';
import 'analyzers/widget_property_analyzer.dart';
import 'project_index.dart';

class AnalysisEngine {
  final WidgetAnalyzer _widgetAnalyzer;
  final ScreenAnalyzer _screenAnalyzer;
  final HierarchyAnalyzer _hierarchyAnalyzer;
  final NavigationAnalyzer _navigationAnalyzer;
  final DependencyAnalyzer _dependencyAnalyzer;
  final StateAnalyzer _stateAnalyzer;
  final CallbackAnalyzer _callbackAnalyzer;
  final WidgetPropertyAnalyzer _propertyAnalyzer;
  final ScreenContextAnalyzer _screenContextAnalyzer;
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
    ScreenContextAnalyzer screenContextAnalyzer = const ScreenContextAnalyzer(),
    ArchitectureHealthAnalyzer healthAnalyzer = const ArchitectureHealthAnalyzer(),
  })  : _widgetAnalyzer = widgetAnalyzer,
        _screenAnalyzer = screenAnalyzer,
        _hierarchyAnalyzer = hierarchyAnalyzer,
        _navigationAnalyzer = navigationAnalyzer,
        _dependencyAnalyzer = dependencyAnalyzer,
        _stateAnalyzer = stateAnalyzer,
        _callbackAnalyzer = callbackAnalyzer,
        _propertyAnalyzer = propertyAnalyzer,
        _screenContextAnalyzer = screenContextAnalyzer,
        _healthAnalyzer = healthAnalyzer;

  AnalysisResult analyse(ParserResult parserResult,
      {required String projectPath, String outputDirectory = 'output/analysis'}) {
    final index = ProjectIndex.build(
      [
        for (final unit in parserResult.resolvedUnits)
          SourceUnit(path: unit.path, unit: unit.unit),
      ],
      projectPath: projectPath,
    );

    final widgets = _widgetAnalyzer.analyse(index);
    final navigation = _navigationAnalyzer.analyse(index);
    final screens = _screenAnalyzer.analyse(
      index,
      widgets,
      navigationTargets: {
        for (final edge in navigation)
          if (!edge.isRouteName) edge.toScreen,
      },
    );
    final dependencies = _dependencyAnalyzer.analyse(parserResult, widgets);

    return AnalysisResult(
      totalFiles: parserResult.totalFiles,
      projectInfo: index.info,
      widgets: widgets,
      screens: screens,
      hierarchy: _hierarchyAnalyzer.analyse(index),
      navigation: navigation,
      dependencies: dependencies,
      states: _stateAnalyzer.analyse(parserResult, outputDirectory: outputDirectory),
      callbacks: _callbackAnalyzer.analyse(index),
      properties: _propertyAnalyzer.analyse(parserResult),
      screenContexts: _screenContextAnalyzer.analyse(index, screens),
      routes: const RouteTable().build(index.units, index.widgetClasses.keys.toSet()),
      unitTargets: const UnitTargetAnalyzer().analyse(index),
      classImports: {
        for (final entry in index.classes.entries)
          if (entry.value.isNotEmpty && index.importUriFor(entry.value.first.path) != null)
            entry.key: index.importUriFor(entry.value.first.path)!,
      },
      architectureHealth: _healthAnalyzer.analyse(
        dependencies: dependencies,
        navigation: navigation,
      ),
    );
  }
}
