import 'package:analyzer/dart/ast/ast.dart';

class ASTModel {
  const ASTModel({
    required this.filePath,
    required this.compilationUnit,
  });

  final String filePath;

  final CompilationUnit compilationUnit;
}
