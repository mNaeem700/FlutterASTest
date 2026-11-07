import 'package:flutterastest/pkg/models/knowledge_graph.dart';

/// PKG serialization (Doc 9.17.1): JSON-LD is primary, GraphML is optional
/// for visualization and external graph analysis.
class GraphSerializer {
  const GraphSerializer();

  static const _vocabulary = 'https://flutterastest.dev/pkg#';

  Map<String, dynamic> toJsonLd(KnowledgeGraph graph, {required String packageName}) {
    final outgoing = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final edge in graph.edges) {
      (outgoing[edge.sourceId] ??= {}).putIfAbsent(edge.type.name, () => []).add({
        '@id': edge.targetId,
        if (edge.order != 0) 'order': edge.order,
        if (edge.label != null) 'label': edge.label,
      });
    }
    return {
      '@context': {'@vocab': _vocabulary, 'label': 'http://www.w3.org/2000/01/rdf-schema#label'},
      '@id': 'pkg:$packageName',
      'graphVersion': '1.0',
      '@graph': [
        for (final node in graph.nodes)
          {
            '@id': node.id,
            '@type': node.type.name,
            'label': node.label,
            ...node.properties,
            ...?outgoing[node.id],
          },
      ],
    };
  }

  String toGraphMl(KnowledgeGraph graph) {
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
    final out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<graphml xmlns="http://graphml.graphdrawing.org/xmlns">')
      ..writeln('  <key id="label" for="node" attr.name="label" attr.type="string"/>')
      ..writeln('  <key id="type" for="node" attr.name="type" attr.type="string"/>')
      ..writeln('  <key id="relation" for="edge" attr.name="relation" attr.type="string"/>')
      ..writeln('  <graph edgedefault="directed">');
    for (final n in graph.nodes) {
      out.writeln('    <node id="${esc(n.id)}"><data key="label">${esc(n.label)}</data>'
          '<data key="type">${n.type.name}</data></node>');
    }
    for (final e in graph.edges) {
      out.writeln('    <edge source="${esc(e.sourceId)}" target="${esc(e.targetId)}">'
          '<data key="relation">${e.type.name}</data></edge>');
    }
    out
      ..writeln('  </graph>')
      ..writeln('</graphml>');
    return out.toString();
  }
}
