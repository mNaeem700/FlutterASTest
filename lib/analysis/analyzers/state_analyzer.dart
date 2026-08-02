import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutterastest/parser/models/parser_result.dart';
import '../models/state_model.dart';
import '../models/state_variable.dart';
import '../models/state_mutation.dart';

class StateAnalyzer {
  const StateAnalyzer();

  List<StateModel> analyse(ParserResult parserResult, {String? projectPath}) {
    final Map<String, StateModel> uniqueStates = {};

    for (final unitResult in parserResult.resolvedUnits) {
      final visitor = _StateVisitor(unitResult.lineInfo);
      unitResult.unit.accept(visitor);

      for (final state in visitor.states) {
        uniqueStates[state.className] = state;
      }
    }

    final statesList = uniqueStates.values.toList();

    // Print Explainable Formula & Metrics Breakdown for Reviewers
    _printExplainableComplexity(statesList);

    // Optional Export for Evaluation, Tables & Graphs
    if (projectPath != null) {
      _exportStateAnalysis(statesList, projectPath);
    }

    return statesList;
  }

  void _printExplainableComplexity(List<StateModel> states) {
    print('\n========================================');
    print('State Complexity Ranking (Explainable)');
    print('========================================');
    print('Complexity Formula:');
    print(
        'Score = Variables + (Reactive × 3) + (Collections × 2) + (Controllers × 2) + (Repositories × 3) + (Services × 2)\n');

    // Sort descending by complexity score if properties exist, or list them nicely
    for (int i = 0; i < states.length; i++) {
      final s = states[i];

      // Calculate metrics on the fly
      final int totalVars = s.variables.length;
      final int reactiveCount =
          s.variables.where((v) => v.category == 'Reactive').length;
      final int collectionCount =
          s.variables.where((v) => v.category == 'Collection').length;
      final int controllerCount =
          s.variables.where((v) => v.category == 'UI Controller').length;
      final int repositoryCount =
          s.variables.where((v) => v.category == 'Repository').length;
      final int serviceCount =
          s.variables.where((v) => v.category == 'Service').length;

      final int score = totalVars +
          (reactiveCount * 3) +
          (collectionCount * 2) +
          (controllerCount * 2) +
          (repositoryCount * 3) +
          (serviceCount * 2);

      print('${i + 1}. Class : ${s.className}');
      print('   Variables      : $totalVars');
      print('   Reactive       : $reactiveCount');
      print('   Collections    : $collectionCount');
      print('   Controllers    : $controllerCount');
      print('   Repositories   : $repositoryCount');
      print('   Services       : $serviceCount');
      print('   ------------------------------');
      print('   Complexity Score : $score\n');
    }
  }

  void _exportStateAnalysis(List<StateModel> states, String projectPath) {
    try {
      // 1. JSON Export
      final jsonMap = {
        'timestamp': DateTime.now().toIso8601String(),
        'classes': states.map((s) {
          final totalVars = s.variables.length;
          final mutableCount = s.variables.where((v) => !v.isFinal).length;
          final immutableCount = s.variables.where((v) => v.isFinal).length;
          final reactiveCount =
              s.variables.where((v) => v.category == 'Reactive').length;
          final collectionCount =
              s.variables.where((v) => v.category == 'Collection').length;
          final controllerCount =
              s.variables.where((v) => v.category == 'UI Controller').length;
          final repositoryCount =
              s.variables.where((v) => v.category == 'Repository').length;
          final serviceCount =
              s.variables.where((v) => v.category == 'Service').length;
          final complexity = totalVars +
              (reactiveCount * 3) +
              (collectionCount * 2) +
              (controllerCount * 2) +
              (repositoryCount * 3) +
              (serviceCount * 2);

          return {
            'class': s.className,
            'variables': totalVars,
            'mutable': mutableCount,
            'immutable': immutableCount,
            'reactive': reactiveCount,
            'collections': collectionCount,
            'controllers': controllerCount,
            'repositories': repositoryCount,
            'services': serviceCount,
            'complexity': complexity,
            'variable_details': s.variables
                .map((v) => {
                      'name': v.name,
                      'type': v.type,
                      'category': v.category,
                      'final': v.isFinal,
                      'late': v.isLate,
                      'nullable': v.isNullable,
                      'static': v.isStatic,
                    })
                .toList(),
          };
        }).toList(),
      };

      final jsonFile = File('$projectPath/state_analysis.json');
      jsonFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(jsonMap));

      // 2. CSV Summary Export
      final csvBuffer = StringBuffer();
      csvBuffer.writeln(
          'Class,Variables,Mutable,Immutable,Reactive,Collections,Controllers,Repositories,Services,Complexity');

      for (var s in states) {
        final totalVars = s.variables.length;
        final mutableCount = s.variables.where((v) => !v.isFinal).length;
        final immutableCount = s.variables.where((v) => v.isFinal).length;
        final reactiveCount =
            s.variables.where((v) => v.category == 'Reactive').length;
        final collectionCount =
            s.variables.where((v) => v.category == 'Collection').length;
        final controllerCount =
            s.variables.where((v) => v.category == 'UI Controller').length;
        final repositoryCount =
            s.variables.where((v) => v.category == 'Repository').length;
        final serviceCount =
            s.variables.where((v) => v.category == 'Service').length;
        final complexity = totalVars +
            (reactiveCount * 3) +
            (collectionCount * 2) +
            (controllerCount * 2) +
            (repositoryCount * 3) +
            (serviceCount * 2);

        csvBuffer
            .writeln('${s.className},$totalVars,$mutableCount,$immutableCount,'
                '$reactiveCount,$collectionCount,$controllerCount,'
                '$repositoryCount,$serviceCount,$complexity');
      }

      final csvFile = File('$projectPath/state_analysis.csv');
      csvFile.writeAsStringSync(csvBuffer.toString());

      print(
          '[INFO] Successfully exported state_analysis.json and state_analysis.csv');
    } catch (e) {
      print('[WARNING] Failed to export state metrics: $e');
    }
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
    // Refined External Resource category types
    const externalTypes = {
      'File',
      'XFile',
      'Uint8List',
      'ByteData',
      'Directory',
      'IOSink',
      'RandomAccessFile'
    };
    if (externalTypes.contains(type)) return 'External Resource';
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
          declaredVariables.add(varName);
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

    for (final member in node.members) {
      if (member is MethodDeclaration) {
        final prevMethod = currentMethod;
        currentMethod = member.name.lexeme;

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
        mutations: mutations,
      ),
    );

    currentClass = previousClass;
  }
}

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
