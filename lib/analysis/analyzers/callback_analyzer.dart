import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutterastest/parser/models/parser_result.dart';
import '../models/callback_model.dart';

class CallbackAnalyzer {
  const CallbackAnalyzer();

  List<CallbackModel> analyse(ParserResult parserResult) {
    final List<CallbackModel> callbacks = [];

    for (final unitResult in parserResult.resolvedUnits) {
      final visitor = _CallbackVisitor();
      unitResult.unit.accept(visitor);
      callbacks.addAll(visitor.extractedCallbacks);
    }

    _printCallbackAnalysisOutput(callbacks);

    return callbacks;
  }

  void _printCallbackAnalysisOutput(List<CallbackModel> callbacks) {
    final uniqueTypesCount =
        callbacks.map((c) => c.callbackName).toSet().length;
    final asyncCount = callbacks.where((c) => c.isAsync).length;
    final navCount = callbacks.where((c) => c.isNavigation).length;
    final stateChangingCount =
        callbacks.where((c) => c.stateChange != 'None').length;

    // Calculate Callback Type Breakdown frequencies
    final Map<String, int> typeBreakdown = {};
    for (final c in callbacks) {
      typeBreakdown[c.callbackName] = (typeBreakdown[c.callbackName] ?? 0) + 1;
    }
    final sortedTypes = typeBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    print('\nCallback Analysis');
    print('-----------------');
    print('Callbacks discovered : ${callbacks.length}');
    print('Unique callback types : $uniqueTypesCount');
    print('Async callbacks : $asyncCount');
    print('Navigation callbacks : $navCount');
    print('State-changing callbacks : $stateChangingCount\n');

    print('Callback Types');
    print('--------------');
    for (final entry in sortedTypes) {
      final dots = '.' * ((21 - entry.key.length).clamp(3, 21));
      print('${entry.key} $dots ${entry.value}');
    }
    print('');

    print('Callback Sample');
    print('========================');
    final sampleLimit = callbacks.length > 3 ? 3 : callbacks.length;
    for (int i = 0; i < sampleLimit; i++) {
      final cb = callbacks[i];
      print('Widget : ${cb.widgetName}');
      print('Callback : ${cb.callbackName}');
      print('Receiver : ${cb.receiver}');
      print('Method : ${cb.invokedMethod}');
      print('Async : ${cb.isAsync}');
      print('Navigation : ${cb.isNavigation}');
      if (cb.isNavigation && cb.targetScreen != null) {
        print('Target Screen : ${cb.targetScreen}');
      }
      print('State Change : ${cb.stateChange}');
      print('------------------------');
    }
    print('');

    final controllerCount = callbacks
        .where((c) => c.receiver != 'Unknown' && c.receiver.isNotEmpty)
        .length;
    final setStateCount =
        callbacks.where((c) => c.stateChange == 'setState').length;
    final rxCount = callbacks
        .where((c) => c.stateChange == 'Rx' || c.stateChange == 'update()')
        .length;

    print('Callback Summary');
    print('================');
    print('Callbacks : ${callbacks.length}');
    print('Navigation callbacks : $navCount');
    print('Async callbacks : $asyncCount');
    print('Controller callbacks : $controllerCount');
    print('setState callbacks : $setStateCount');
    print('Rx callbacks : $rxCount');
    print('Unique callback types : $uniqueTypesCount\n');
  }
}

class _CallbackVisitor extends RecursiveAstVisitor<void> {
  final List<CallbackModel> extractedCallbacks = [];
  String? currentWidget;

  static const targetCallbacks = {
    'onPressed',
    'onTap',
    'onLongPress',
    'onChanged',
    'onSubmitted',
    'onEditingComplete',
    'onWillPop',
    'onRefresh',
    'onPageChanged',
    'onDismissed',
    'onAccept',
    'onSelected',
    'onExpansionChanged'
  };

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructorName = node.constructorName.type.toSource();
    final previousWidget = currentWidget;
    currentWidget = constructorName;

    for (final argument in node.argumentList.arguments) {
      if (argument is NamedExpression) {
        final fieldName = argument.name.label.name;
        if (targetCallbacks.contains(fieldName)) {
          _parseCallbackExpression(
              currentWidget ?? 'UnknownWidget', fieldName, argument.expression);
        }
      }
    }

    super.visitInstanceCreationExpression(node);
    currentWidget = previousWidget;
  }

  void _parseCallbackExpression(
      String widgetName, String callbackName, Expression expression) {
    bool isAsync = false;
    bool isNavigation = false;
    String? targetScreen;
    String stateChange = 'None';
    String receiver = 'Unknown';
    String invokedMethod = 'action()';

    final source = expression.toSource();
    if (source.contains('async')) {
      isAsync = true;
    }

    // Navigation and Target Screen Resolution
    if (source.contains('Navigator') ||
        source.contains('Get.to') ||
        source.contains('Get.off')) {
      isNavigation = true;
      final screenMatch =
          RegExp(r'([A-Z][a-zA-Z0-9]+Screen)').firstMatch(source);
      if (screenMatch != null) {
        targetScreen = screenMatch.group(1);
      } else {
        targetScreen = 'HomeScreen';
      }
    }

    // State Change Classification
    if (source.contains('setState')) {
      stateChange = 'setState';
    } else if (source.contains('update()')) {
      stateChange = 'update()';
    } else if (source.contains('.value') || source.contains('Rx')) {
      stateChange = 'Rx';
    } else if (source.contains('ValueNotifier')) {
      stateChange = 'ValueNotifier';
    } else if (source.contains('ChangeNotifier')) {
      stateChange = 'ChangeNotifier';
    }

    // Advanced Semantic Receiver & Method Extraction (Cleaning Get.find<AuthController>())
    if (source.contains('Get.find<') || source.contains('find<')) {
      final findMatch = RegExp(
              r'(?:Get\.)?find<([a-zA-Z0-9_]+)>\s*\(\)\s*\.\s*([a-zA-Z0-9_]+\s*\([^)]*\))')
          .firstMatch(source);
      if (findMatch != null) {
        receiver = findMatch.group(1) ?? 'Unknown';
        invokedMethod = findMatch.group(2) ?? 'action()';
      } else {
        final classOnlyMatch =
            RegExp(r'(?:Get\.)?find<([a-zA-Z0-9_]+)>').firstMatch(source);
        if (classOnlyMatch != null) {
          receiver = classOnlyMatch.group(1) ?? 'Unknown';
        }
      }
    } else if (source.contains('.')) {
      final parts = source.split('.');
      if (parts.length >= 2) {
        final potentialReceiver =
            parts[0].replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
        if (potentialReceiver.isNotEmpty) {
          receiver = potentialReceiver;
        }
        final methodPart = parts[1].split('(').first;
        if (methodPart.isNotEmpty) {
          invokedMethod = '$methodPart()';
        }
      }
    }

    extractedCallbacks.add(
      CallbackModel(
        widgetName: widgetName,
        callbackName: callbackName,
        invokedMethod: invokedMethod,
        receiver: receiver,
        isAsync: isAsync,
        isNavigation: isNavigation,
        targetScreen: targetScreen,
        stateChange: stateChange,
      ),
    );
  }
}
