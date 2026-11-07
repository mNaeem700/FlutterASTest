import '../context_builder/context_builder.dart';
import '../pkg/models/knowledge_graph.dart';
import '../pkg/models/pkg_edge.dart';
import '../pkg/models/pkg_node.dart';
import 'models/prompt_context.dart';

/// Renders the context of each screen from the entities the Context Builder
/// selected from the PKG. Nothing is read from the AST here: if a fact is not
/// in the package, it is not in the prompt.
class PromptContextGenerator {
  const PromptContextGenerator({
    this.config = const ContextConfiguration(),
    this.keepDelegated = true,
  });

  final ContextConfiguration config;

  /// False hides facts found by following calls into other classes (A1).
  final bool keepDelegated;

  List<PromptContext> generate(KnowledgeGraph graph) {
    final screens = graph.nodesOfType(NodeType.screen)
      ..sort((a, b) => a.label.compareTo(b.label));
    final builder = ContextBuilder(config: config);
    return [
      for (final screen in screens)
        _render(
            graph,
            screen,
            builder.build(graph, screen,
                estimateTokens: (draft) => _render(graph, screen, draft).context.length ~/ 4)),
    ];
  }

  PromptContext _render(KnowledgeGraph fullGraph, PkgNode screen, ContextPackage package) {
    final graph = _SelectedGraph(fullGraph, package);
    final visited = <String>{screen.id};
    final out = StringBuffer();

    final importUri = screen.property<String>('importUri');
    final isStateful = screen.property<bool>('isStateful') ?? false;
    final stateClass = screen.property<String>('stateClass');

    out.writeln('### Screen under test');
    out.writeln('- Class: `${screen.label}` '
        '(${isStateful ? 'StatefulWidget, state class `$stateClass`' : 'StatelessWidget'})');
    out.writeln(importUri == null
        ? '- Import: not importable (file is outside lib/: ${screen.property<String>('filePath')})'
        : "- Import: `import '$importUri';`");
    for (final constructor in screen.stringList('constructors')) {
      out.writeln('- Constructor: `$constructor`');
    }

    out.writeln('\n### Widget tree returned by build()');
    final roots = graph.visibleChildren(screen.id);
    if (roots.isEmpty) {
      out.writeln('Not extractable statically (build() returns a value computed at runtime).');
    } else {
      for (var i = 0; i < roots.length; i++) {
        _renderWidget(graph, roots[i], '', i == roots.length - 1, out, visited, isRoot: true);
      }
      if (screen.property<bool>('treeTruncated') == true) {
        out.writeln('(tree truncated: large screen, deeper widgets omitted)');
      }
    }

    out.writeln('\n### User interactions');
    final interactions = <String>[];
    for (final root in roots) {
      _collectInteractions(graph, root, interactions, visited);
    }
    if (interactions.isEmpty) {
      out.writeln('None found.');
    } else {
      for (var i = 0; i < interactions.length; i++) {
        out.writeln('${i + 1}. ${interactions[i]}');
      }
    }

    final hooks = graph.targets(screen.id, EdgeType.hasLifecycle);
    if (hooks.isNotEmpty) {
      out.writeln('\n### Lifecycle');
      for (final hook in hooks) {
        visited.add(hook.id);
        final effects = _describeAction(graph, hook, visited);
        out.writeln('- `${hook.label}`${effects.isEmpty ? '' : ': $effects'}');
      }
    }

    final fields = graph.targets(screen.id, EdgeType.bindsState);
    out.writeln('\n### State fields${stateClass == null ? '' : ' of `$stateClass`'}');
    if (fields.isEmpty) {
      out.writeln('None.');
    } else {
      for (final field in fields) {
        visited.add(field.id);
        out.writeln('- `${field.property<String>('declaration') ?? field.label}`');
      }
    }

    final navigationImports = <String>{};
    out.writeln('\n### Dependencies');
    final dependencyEdges = graph.outgoing(screen.id, EdgeType.dependsOn);
    final usedMembers = graph.targets(screen.id, EdgeType.uses);
    if (dependencyEdges.isEmpty) {
      out.writeln('None detected.');
    } else {
      for (final edge in dependencyEdges) {
        final dependency = graph.getNode(edge.targetId)!;
        visited.add(dependency.id);
        final origin = dependency.property<bool>('isProjectClass') == true
            ? 'project class'
            : 'external class';
        final how = (edge.label?.isEmpty ?? true) ? 'used directly' : 'obtained via ${edge.label}';
        out.writeln('- `${dependency.label}` ($origin, $how)');
        final dependencyImport = dependency.property<String>('importUri');
        if (dependencyImport != null) {
          navigationImports.add(dependencyImport);
          out.writeln("  - Import: `import '$dependencyImport';`");
        }
        for (final constructor in dependency.stringList('constructors')) {
          out.writeln('  - Constructor: `$constructor`');
        }
        final members = usedMembers.where((m) =>
            graph.outgoing(dependency.id, EdgeType.declares).any((e) => e.targetId == m.id));
        for (final member in members) {
          visited.add(member.id);
          out.writeln('  - `${member.property<String>('signature') ?? member.label}`');
        }
      }
    }

    out.writeln('\n### Navigation');
    final destinations = <String>{};
    for (final edge in graph.outgoing(screen.id, EdgeType.navigatesTo)) {
      final target = graph.getNode(edge.targetId)!;
      visited.add(target.id);
      destinations.add(_describeDestination(target, edge.label, navigationImports));
    }
    if (destinations.isEmpty) {
      out.writeln('None.');
    } else {
      for (final destination in destinations) {
        out.writeln('- $destination');
      }
    }

    return PromptContext(
      screenName: screen.label,
      screenId: screen.id,
      importUri: importUri,
      context: out.toString().trim(),
      navigationImports: navigationImports.toList()..sort(),
      nodesVisited: visited.length,
      metrics: package.metrics(),
    );
  }

  void _renderWidget(_SelectedGraph graph, PkgNode node, String prefix, bool isLast,
      StringBuffer out, Set<String> visited,
      {bool isRoot = false}) {
    visited.add(node.id);
    final events = [
      for (final interaction in graph.targets(node.id, EdgeType.triggers)) interaction.label,
    ];
    final parts = <String>[
      node.label,
      for (final label in node.stringList('labels')) '"${_escape(label)}"',
      if (node.property<String>('key') != null) "key: '${node.property<String>('key')}'",
      if (events.isNotEmpty) '{${events.join(', ')}}',
      for (final rule in graph.targets(node.id, EdgeType.validates))
        'validator: "${_escape(rule.label)}"',
    ];

    final connector = isRoot ? '' : (isLast ? '└─ ' : '├─ ');
    out.writeln('$prefix$connector${parts.join(' ')}');

    for (final rule in graph.targets(node.id, EdgeType.validates)) {
      visited.add(rule.id);
    }
    final children = graph.visibleChildren(node.id);
    final childPrefix = isRoot ? '' : '$prefix${isLast ? '   ' : '│  '}';
    for (var i = 0; i < children.length; i++) {
      _renderWidget(graph, children[i], childPrefix, i == children.length - 1, out, visited);
    }
  }

  void _collectInteractions(
      _SelectedGraph graph, PkgNode widget, List<String> out, Set<String> visited) {
    for (final interaction in graph.targets(widget.id, EdgeType.triggers)) {
      visited.add(interaction.id);
      final labels = widget.stringList('labels');
      final key = widget.property<String>('key');
      final inner = labels.isEmpty ? _firstLabel(graph, widget) : null;
      final subject = [
        '`${widget.label}`',
        if (labels.isNotEmpty) '"${_escape(labels.first)}"',
        if (inner != null) 'containing "${_escape(inner)}"',
        if (key != null) "(key: '$key')",
      ].join(' ');
      final action = _describeAction(graph, interaction, visited);
      out.add('$subject — `${interaction.label}`'
          '${action.isEmpty ? ': no statically visible effect' : ': $action'}');
    }
    for (final child in graph.visibleChildren(widget.id)) {
      _collectInteractions(graph, child, out, visited);
    }
  }

  /// Keeps multi-line texts on one line so the tree stays readable; the
  /// escapes match how the text must be written in a Dart finder.
  static String _escape(String text) =>
      text.replaceAll('\\', r'\\').replaceAll('\n', r'\n').replaceAll('"', r'\"');

  /// First label inside [widget], skipping descendants that handle events
  /// themselves: their text identifies them, not the wrapper.
  String? _firstLabel(_SelectedGraph graph, PkgNode widget) {
    for (final child in graph.visibleChildren(widget.id)) {
      if (graph.outgoing(child.id, EdgeType.triggers).isNotEmpty) continue;
      final labels = child.stringList('labels');
      if (labels.isNotEmpty) return labels.first;
      final nested = _firstLabel(graph, child);
      if (nested != null) return nested;
    }
    return null;
  }

  String _describeAction(_SelectedGraph graph, PkgNode action, Set<String> visited) {
    final parts = <String>[];
    final calls = action.stringList('calls');
    if (calls.isNotEmpty) parts.add('calls ${calls.map((c) => '`$c`').join(', ')}');
    for (final edge in graph.outgoing(action.id, EdgeType.navigatesTo)) {
      final target = graph.getNode(edge.targetId)!;
      visited.add(target.id);
      parts.add(target.type == NodeType.screen
          ? 'navigates with `${edge.label}` to `${target.label}`'
          : target.property<bool>('isPrevious') == true
              ? 'goes back with `${edge.label}`'
              : 'navigates with `${edge.label}` to route "${target.label}"');
    }
    bool local(String fact) => keepDelegated || !fact.contains(' (in ');
    final stateChanges = action.stringList('stateChanges').where(local).toList();
    if (stateChanges.isNotEmpty) parts.add('changes state (${stateChanges.join(', ')})');
    final effects = action.stringList('effects').where(local).toList();
    if (effects.isNotEmpty) parts.add('shows/starts ${effects.join(', ')}');
    if (action.property<bool>('isAsync') == true) parts.add('async');
    return parts.join('; ');
  }

  String _describeDestination(PkgNode target, String? api, Set<String> imports) {
    if (target.type == NodeType.screen) {
      final uri = target.property<String>('importUri');
      if (uri != null) imports.add(uri);
      return '`$api` → `${target.label}`${uri == null ? '' : " (import '$uri')"}';
    }
    if (target.property<bool>('isPrevious') == true) return '`$api` → previous route';
    return target.property<bool>('isRouteName') == true
        ? '`$api` → route "${target.label}"'
        : '`$api` → `${target.label}` (not analysed as a screen)';
  }
}

/// The PKG as the renderer sees it: only selected nodes, with collapsed layout
/// wrappers replaced by their children.
class _SelectedGraph {
  _SelectedGraph(this._graph, this._package);

  final KnowledgeGraph _graph;
  final ContextPackage _package;

  List<PkgEdge> outgoing(String id, EdgeType type) => [
        for (final edge in _graph.outgoing(id, type))
          if (_package.selected.contains(edge.targetId)) edge,
      ];

  List<PkgNode> targets(String id, EdgeType type) => [
        for (final edge in outgoing(id, type)) _graph.getNode(edge.targetId)!,
      ];

  PkgNode? getNode(String id) => _graph.getNode(id);

  List<PkgNode> visibleChildren(String id) => [
        for (final child in targets(id, EdgeType.contains))
          if (_package.collapsed.contains(child.id)) ...visibleChildren(child.id) else child,
      ];
}
