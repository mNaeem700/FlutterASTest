import '../analysis/analysis_result.dart';
import '../context_builder/context_builder.dart';
import '../experiment/experiment_config.dart';
import '../orchestrator/contracts/pipeline_module.dart';
import '../orchestrator/pipeline_context.dart';
import '../orchestrator/pipeline_stage.dart';
import '../pkg/models/knowledge_graph.dart';
import '../pkg/models/pkg_edge.dart';
import 'baseline_context_generator.dart';
import 'models/prompt_context.dart';
import 'prompt_context_generator.dart';

class PromptModule implements PipelineModule {
  const PromptModule({BaselineContextGenerator baseline = const BaselineContextGenerator()})
      : _baseline = baseline;

  final BaselineContextGenerator _baseline;

  /// Relationships between entities; without them only local structure is left.
  static const _linkEdges = {
    EdgeType.dependsOn,
    EdgeType.uses,
    EdgeType.declares,
    EdgeType.calls,
    EdgeType.navigatesTo,
  };

  @override
  PipelineStage get stage => PipelineStage.contextBuilder;

  @override
  Future<void> execute(PipelineContext context) async {
    final config = context.get<ExperimentConfig>() ?? const ExperimentConfig();
    final all = config.mode == ContextMode.pkg
        ? _fromGraph(context, config)
        : _fromSource(context, config);
    final chosen = config.screens.isEmpty
        ? all
        : [for (final c in all) if (config.screens.contains(c.screenName)) c];
    final contexts = sample(chosen, config.maxScreens);
    if (contexts.isEmpty && config.screens.isNotEmpty) {
      throw Exception('No analysed screen is named ${config.screens.join(', ')}. '
          'Screens found: ${all.map((c) => c.screenName).join(', ')}');
    }
    context.put<List<PromptContext>>(contexts);
    print('Generated context for ${contexts.length} screens.');
  }

  /// Evenly spaced over the name-sorted list, so every mode picks the same screens.
  static List<T> sample<T>(List<T> items, int? limit) => limit == null || items.length <= limit
      ? items
      : [for (var i = 0; i < limit; i++) items[i * items.length ~/ limit]];

  List<PromptContext> _fromGraph(PipelineContext context, ExperimentConfig config) {
    final graph = context.get<KnowledgeGraph>();
    if (graph == null) {
      throw Exception('KnowledgeGraph missing from PipelineContext!');
    }
    print('\nBuilding prompt contexts from the PKG...');
    print('----------------------------------------');

    final noLinks = config.ablation == Ablation.noPkgLinks;
    final contexts = PromptContextGenerator(
      keepDelegated: !noLinks,
      config: ContextConfiguration(
        tokenBudget: config.tokenBudget,
        enabled: config.ablation != Ablation.noContextBuilder,
        excludedEdges: noLinks ? _linkEdges : const {},
      ),
    ).generate(graph);
    for (final c in contexts) {
      print('${c.screenName.padRight(32)} ${c.nodesVisited.toString().padLeft(4)} PKG nodes');
    }
    return contexts;
  }

  List<PromptContext> _fromSource(PipelineContext context, ExperimentConfig config) {
    final analysis = context.get<AnalysisResult>();
    if (analysis == null) {
      throw Exception('AnalysisResult missing from PipelineContext!');
    }
    print('\nBuilding ${config.mode.name} contexts from source files...');
    print('--------------------------------------------------');

    final path = context.projectPath;
    final contexts = switch (config.mode) {
      ContextMode.file => _baseline.generateFileLevel(analysis, projectPath: path),
      ContextMode.repository => _baseline.generateRepository(analysis, projectPath: path),
      _ => _baseline.generate(analysis, projectPath: path),
    };
    for (final c in contexts) {
      print('${c.screenName.padRight(32)} ${c.context.length.toString().padLeft(8)} chars');
    }
    return contexts;
  }
}
