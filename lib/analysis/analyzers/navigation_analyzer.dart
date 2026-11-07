import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../flutter_ast/action_summarizer.dart';
import '../models/navigation_edge.dart';
import '../project_index.dart';

/// Navigation edges from every class in the project. A State class is reported
/// under its widget's name so edges connect screens.
class NavigationAnalyzer {
  const NavigationAnalyzer();

  List<NavigationEdge> analyse(ProjectIndex index) {
    final detector = NavigationDetector(knownWidgets: index.widgetClasses.keys.toSet());
    final widgetOfState = {
      for (final entry in index.stateClassOf.entries) entry.value.name: entry.key,
    };
    final edges = <NavigationEdge>{};

    for (final refs in index.classes.values) {
      for (final ref in refs) {
        final source = widgetOfState[ref.name] ?? ref.name;
        ref.declaration.accept(_Visitor(detector, source, edges));
      }
    }

    final sorted = edges.toList()
      ..sort((a, b) => '${a.fromScreen}${a.toScreen}${a.api}'
          .compareTo('${b.fromScreen}${b.toScreen}${b.api}'));
    return sorted;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this._detector, this._source, this._edges);

  final NavigationDetector _detector;
  final String _source;
  final Set<NavigationEdge> _edges;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = _detector.detect(node);
    if (target?.target != null) {
      _edges.add(NavigationEdge(
        fromScreen: _source,
        toScreen: target!.target!,
        api: target.api,
        kind: target.kind,
        isRouteName: target.isRouteName,
      ));
    }
    super.visitMethodInvocation(node);
  }
}
