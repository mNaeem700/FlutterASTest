import '../analysis/models/screen_context_model.dart';
import 'lcov.dart';
import 'models/test_run.dart';

/// Measures Doc 16.9's Flutter-specific coverage by mapping lcov line hits
/// onto what static analysis found in the screen.
///
/// lcov is line-based: a one-line closure on the same line as its widget
/// counts as run when the widget is built, which over-approximates
/// interaction coverage for such handlers.
class StructuralCoverageAnalyzer {
  const StructuralCoverageAnalyzer();

  StructuralCoverage analyse(ScreenContextModel screen, LcovReport report) {
    bool hit(SourceLocation location) {
      final lines = report.files[location.file];
      if (lines == null) return false;
      return location.lines.any((line) => (lines[line] ?? 0) > 0);
    }

    bool lineHit(SourceLocation location) =>
        (report.files[location.file]?[location.line] ?? 0) > 0;

    final widgets = [
      for (final widget in screen.allWidgets)
        if (widget.location != null) widget,
    ];
    final interactions = [
      for (final interaction in screen.interactions)
        if (interaction.bodyLocation != null) interaction,
    ];
    final navigation = screen.sites.where((s) => s.kind == SiteKind.navigation).toList();
    final state = screen.sites.where((s) => s.kind == SiteKind.stateChange).toList();

    return StructuralCoverage(
      widgets: Ratio(widgets.where((w) => lineHit(w.location!)).length, widgets.length),
      interactions:
          Ratio(interactions.where((i) => hit(i.bodyLocation!)).length, interactions.length),
      navigation: Ratio(navigation.where((s) => lineHit(s.location)).length, navigation.length),
      state: Ratio(state.where((s) => lineHit(s.location)).length, state.length),
      uncoveredInteractions: [
        for (final i in interactions)
          if (!hit(i.bodyLocation!))
            '`${i.widgetType}`${i.label == null ? '' : ' "${i.label}"'} ${i.event} '
                '(${i.bodyLocation!.file}:${i.bodyLocation!.line})',
      ],
      uncoveredNavigation: [
        for (final s in navigation)
          if (!lineHit(s.location)) '${s.description} (${s.location.file}:${s.location.line})',
      ],
      uncoveredState: [
        for (final s in state)
          if (!lineHit(s.location)) '${s.description} (${s.location.file}:${s.location.line})',
      ],
    );
  }
}
