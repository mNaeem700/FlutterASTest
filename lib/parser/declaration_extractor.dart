import 'package:analyzer/dart/ast/ast.dart';
import 'models/declaration_model.dart';
import 'models/declaration_type.dart';

class DeclarationExtractor {
  const DeclarationExtractor();

  List<DeclarationModel> extract({
    required CompilationUnit unit,
    required String filePath,
  }) {
    final declarations = <DeclarationModel>[];

    for (final member in unit.declarations) {
      switch (member) {
        case ClassDeclaration():
          declarations.add(
            _createDeclaration(
              name: member.name.lexeme,
              type: DeclarationType.classDeclaration,
              filePath: filePath,
              node: member,
            ),
          );
        case EnumDeclaration():
          declarations.add(
            _createDeclaration(
              name: member.name.lexeme,
              type: DeclarationType.enumDeclaration,
              filePath: filePath,
              node: member,
            ),
          );
        case MixinDeclaration():
          declarations.add(
            _createDeclaration(
              name: member.name.lexeme,
              type: DeclarationType.mixinDeclaration,
              filePath: filePath,
              node: member,
            ),
          );
        case ExtensionDeclaration():
          declarations.add(
            _createDeclaration(
              name: member.name?.lexeme ?? '<anonymous>',
              type: DeclarationType.extensionDeclaration,
              filePath: filePath,
              node: member,
            ),
          );
        case FunctionDeclaration():
          declarations.add(
            _createDeclaration(
              name: member.name.lexeme,
              type: DeclarationType.functionDeclaration,
              filePath: filePath,
              node: member,
            ),
          );
        case TopLevelVariableDeclaration():
          for (final variable in member.variables.variables) {
            declarations.add(
              DeclarationModel(
                name: variable.name.lexeme,
                type: DeclarationType.topLevelVariable,
                filePath: filePath,
                offset: variable.offset,
                endOffset: variable.end,
                // Yahan _annotations pass ho raha hai
                annotations: _annotations(member.metadata),
                modifiers: _modifiers(member),
              ),
            );
          }
        case TypeAlias():
          declarations.add(
            _createDeclaration(
              name: member.name.lexeme,
              type: DeclarationType.typedefDeclaration,
              filePath: filePath,
              node: member,
            ),
          );
        default:
          break;
      }
    }

    return List.unmodifiable(declarations);
  }

  DeclarationModel _createDeclaration({
    required String name,
    required DeclarationType type,
    required String filePath,
    required AstNode node,
  }) {
    final metadata = switch (node) {
      AnnotatedNode() => node.metadata,
      _ => const <Annotation>[],
    };

    return DeclarationModel(
      name: name,
      type: type,
      filePath: filePath,
      offset: node.offset,
      endOffset: node.end,
      annotations: _annotations(metadata),
      modifiers: _modifiers(node),
    );
  }

  // FIX: NodeList<Annotation> ki jagah Iterable<Annotation> kar diya gaya hai
  List<String> _annotations(Iterable<Annotation> metadata) {
    return List.unmodifiable(
      metadata.map((e) => e.name.name),
    );
  }

  List<String> _modifiers(AstNode node) {
    final modifiers = <String>[];

    if (node is ClassDeclaration && node.abstractKeyword != null) {
      modifiers.add('abstract');
    }

    if (node is TopLevelVariableDeclaration) {
      if (node.variables.isConst) modifiers.add('const');
      if (node.variables.isFinal) modifiers.add('final');
      if (node.variables.lateKeyword != null) modifiers.add('late');
    }

    return List.unmodifiable(modifiers);
  }
}
