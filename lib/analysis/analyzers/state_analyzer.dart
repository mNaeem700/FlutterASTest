import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutterastest/parser/models/parser_result.dart';
import '../models/state_model.dart';
import '../models/state_variable.dart';
import '../models/state_mutation.dart'; // 👇 ADDED MUTATION MODEL

class StateAnalyzer {
  const StateAnalyzer();

  List<StateModel> analyse(ParserResult parserResult) {
    final Map<String, StateModel> uniqueStates = {};

    for (final unitResult in parserResult.resolvedUnits) {
      final visitor = _StateVisitor(
          unitResult.lineInfo); // Pass lineInfo for accurate line numbers
      unitResult.unit.accept(visitor);

      for (final state in visitor.states) {
        uniqueStates[state.className] = state;
      }
    }

    return uniqueStates.values.toList();
  }
}

class _StateVisitor extends RecursiveAstVisitor<void> {
  _StateVisitor(this.lineInfo);

  final dynamic lineInfo;
  final List<StateModel> states = [];

  String? currentClass;
  String? currentMethod;
  final Set<String> declaredVariables = {};

  bool _isStatefulClass(ClassDeclaration node) {
    final extendsClause = node.extendsClause;
    if (extendsClause == null) return false;

    final superclass = extendsClause.superclass.toSource();

    if (superclass.startsWith('State<') || superclass == 'State') return true;
    if (superclass.startsWith('GetxController')) return true;
    if (superclass.startsWith('ChangeNotifier')) return true;
    if (superclass.startsWith('Cubit')) return true;
    if (superclass.startsWith('Bloc')) return true;

    return false;
  }

  String _classifyType(String type) {
    if (type.startsWith('Rx')) return 'Reactive';
    if (type.contains('Controller')) return 'UI Controller';
    if (type.endsWith('Repo') || type.contains('Repository'))
      return 'Repository';
    if (type.endsWith('Service') || type.contains('ApiClient'))
      return 'Service';
    if (type.startsWith('List<') ||
        type.startsWith('Map<') ||
        type.startsWith('Set<') ||
        type.contains('Iterable')) return 'Collection';
    if (type == 'bool' ||
        type == 'int' ||
        type == 'double' ||
        type == 'String' ||
        type == 'num') return 'Primitive';
    return 'Model';
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (!_isStatefulClass(node)) {
      super.visitClassDeclaration(node);
      return;
    }

    final previousClass = currentClass;
    currentClass = node.name.lexeme;
    declaredVariables.clear();

    final Map<String, StateVariable> uniqueVariables = {};
    final List<StateMutation> mutations = [];

    for (final member in node.members) {
      if (member is FieldDeclaration) {
        final isStatic = member.isStatic;
        final isFinal = member.fields.isFinal;
        final isLate = member.fields.isLate;

        final typeNode = member.fields.type;
        final typeSource = typeNode?.toSource() ?? 'dynamic';
        final isNullable = typeSource.endsWith('?');
        final cleanType = typeSource.replaceAll('?', '');

        for (final variable in member.fields.variables) {
          final varName = variable.name.lexeme;
          declaredVariables
              .add(varName); // Track variables for mutation matching
          uniqueVariables[varName] = StateVariable(
            name: varName,
            type: cleanType,
            isFinal: isFinal,
            isLate: isLate,
            isNullable: isNullable,
            isStatic: isStatic,
            category: _classifyType(cleanType),
          );
        }
      }
    }

    // Temporarily attach visitor context to harvest mutations during method/constructor visits
    // We run standard visitor traversal for members
    for (final member in node.members) {
      if (member is MethodDeclaration) {
        final prevMethod = currentMethod;
        currentMethod = member.name.lexeme;

        // Visit method body for mutations
        member.accept(_MutationVisitor(currentClass!, currentMethod!,
            declaredVariables, lineInfo, mutations));

        currentMethod = prevMethod;
      }
    }

    final sortedVariables = uniqueVariables.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    states.add(
      StateModel(
        className: currentClass!,
        framework: '',
        variables: sortedVariables,
        mutatorMethods: const [],
        triggers: const [],
        mutations: mutations, // 👇 POPULATED MUTATIONS
      ),
    );

    currentClass = previousClass;
  }
}

// Dedicated visitor to detect mutations inside methods
class _MutationVisitor extends RecursiveAstVisitor<void> {
  _MutationVisitor(this.enclosingClass, this.enclosingMethod,
      this.declaredVariables, this.lineInfo, this.mutations);

  final String enclosingClass;
  final String enclosingMethod;
  final Set<String> declaredVariables;
  final dynamic lineInfo;
  final List<StateMutation> mutations;

  int _getLineNumber(AstNode node) {
    try {
      if (lineInfo != null) {
        return lineInfo.getLocation(node.offset).lineNumber;
      }
    } catch (_) {}
    return 0;
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final targetSource = node.leftHandSide.toSource();

    // Check standard assignment or Rx value update (e.g. count.value = 5)
    String? matchedVar;
    String mutationType = 'assignment';

    if (node.operator.lexeme != '=') {
      mutationType = 'compoundAssignment';
    }

    if (declaredVariables.contains(targetSource)) {
      matchedVar = targetSource;
    } else if (targetSource.endsWith('.value')) {
      final baseVar = targetSource.replaceAll('.value', '');
      if (declaredVariables.contains(baseVar)) {
        matchedVar = baseVar;
        mutationType = 'rxUpdate';
      }
    }

    if (matchedVar != null) {
      mutations.add(
        StateMutation(
          variableName: matchedVar,
          enclosingClass: enclosingClass,
          enclosingMethod: enclosingMethod,
          mutationType: mutationType,
          sourceLine: _getLineNumber(node),
        ),
      );
    }

    super.visitAssignmentExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    final operand = node.operand.toSource();
    if (declaredVariables.contains(operand)) {
      mutations.add(
        StateMutation(
          variableName: operand,
          enclosingClass: enclosingClass,
          enclosingMethod: enclosingMethod,
          mutationType: 'incrementDecrement',
          sourceLine: _getLineNumber(node),
        ),
      );
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    final operand = node.operand.toSource();
    if (declaredVariables.contains(operand)) {
      mutations.add(
        StateMutation(
          variableName: operand,
          enclosingClass: enclosingClass,
          enclosingMethod: enclosingMethod,
          mutationType: 'incrementDecrement',
          sourceLine: _getLineNumber(node),
        ),
      );
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource();
    final methodName = node.methodName.name;

    const collectionMethods = {
      'add',
      'remove',
      'clear',
      'insert',
      'addAll',
      'removeWhere',
      'putIfAbsent'
    };
    if (target != null &&
        declaredVariables.contains(target) &&
        collectionMethods.contains(methodName)) {
      mutations.add(
        StateMutation(
          variableName: target,
          enclosingClass: enclosingClass,
          enclosingMethod: enclosingMethod,
          mutationType: 'collectionMutation',
          sourceLine: _getLineNumber(node),
        ),
      );
    }

    super.visitMethodInvocation(node);
  }
}
