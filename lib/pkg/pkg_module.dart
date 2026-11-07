import 'dart:convert';
import 'dart:io';

import 'package:flutterastest/experiment/experiment_config.dart';
import 'package:path/path.dart' as p;

import 'package:flutterastest/analysis/analysis_result.dart';
import 'package:flutterastest/orchestrator/contracts/pipeline_module.dart';
import 'package:flutterastest/orchestrator/pipeline_context.dart';
import 'package:flutterastest/orchestrator/pipeline_stage.dart';
import 'package:flutterastest/pkg/models/knowledge_graph.dart';
import 'package:flutterastest/pkg/models/pkg_node.dart';
import 'package:flutterastest/pkg/graph_serializer.dart';
import 'package:flutterastest/pkg/graph_validator.dart';
import 'package:flutterastest/pkg/pkg_builder.dart';

class PkgModule implements PipelineModule {
  @override
  PipelineStage get stage => PipelineStage.knowledgeGraph;

  @override
  Future<void> execute(PipelineContext context) async {
    print('\nBuilding Program Knowledge Graph (PKG)...');
    print('-----------------------------------------');

    final analysisResult = context.get<AnalysisResult>();
    if (analysisResult == null) {
      throw Exception('AnalysisResult is missing from PipelineContext!');
    }

    final graph = PkgBuilder().build(analysisResult);
    context.put<KnowledgeGraph>(graph);

    print('PKG built: ${graph.nodes.length} nodes, ${graph.edges.length} edges');
    for (final type in NodeType.values) {
      final count = graph.nodesOfType(type).length;
      if (count > 0) print('  ${type.name.padRight(12)} $count');
    }

    final problems = const GraphValidator().validate(graph);
    print(problems.isEmpty ? 'PKG validation passed.' : 'PKG validation problems:');
    problems.forEach(print);

    const serializer = GraphSerializer();
    final directory =
        (context.get<ExperimentConfig>() ?? const ExperimentConfig()).analysisDirectory;
    final file = File(p.join(directory, 'pkg.jsonld'));
    file.parent.createSync(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(
        serializer.toJsonLd(graph, packageName: analysisResult.projectInfo.packageName)));
    await File(p.join(directory, 'pkg.graphml')).writeAsString(serializer.toGraphMl(graph));
    print('PKG exported to ${file.path} (JSON-LD) and pkg.graphml');
  }
}
