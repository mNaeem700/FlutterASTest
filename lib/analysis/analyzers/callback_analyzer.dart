import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../flutter_ast/action_summarizer.dart';
import '../flutter_ast/widget_call.dart';
import '../models/callback_model.dart';
import '../project_index.dart';

/// Every event handler (`onTap`, `onPressed`, …) passed to a widget anywhere
/// in the project, with what the handler does.
class CallbackAnalyzer {
  const CallbackAnalyzer();

  List<CallbackModel> analyse(ProjectIndex index) {
    final detector =
        NavigationDetector(knownWidgets: index.widgetClasses.keys.toSet());
    final callbacks = <CallbackModel>[];

    for (final refs in index.classes.values) {
      for (final ref in refs) {
        final classes = [
          ref.declaration,
          if (index.isWidget(ref.name) && index.stateClassOf[ref.name] != null)
            index.stateClassOf[ref.name]!.declaration,
        ];
        final summarizer =
            ActionSummarizer(methods: methodsOf(classes), navigation: detector);
        ref.declaration.accept(_Visitor(summarizer, callbacks));
      }
    }

    return callbacks;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this._summarizer, this._callbacks);

  final ActionSummarizer _summarizer;
  final List<CallbackModel> _callbacks;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _record(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _record(node);
    super.visitMethodInvocation(node);
  }

  void _record(Expression node) {
    final call = asWidgetCall(node);
    if (call == null) return;

    for (final argument in call.namedArguments) {
      final event = argument.name.label.name;
      if (!RegExp(r'^on[A-Z]').hasMatch(event)) continue;
      if (unwrap(argument.expression) is NullLiteral) continue;

      final action = _summarizer.summarizeHandler(argument.expression);
      final firstCall = action.calls.isEmpty ? null : action.calls.first;
      final dot = firstCall?.lastIndexOf('.') ?? -1;
      final navigation =
          action.navigation.isEmpty ? null : action.navigation.first;

      _callbacks.add(CallbackModel(
        widgetName: call.displayName,
        callbackName: event,
        invokedMethod: firstCall == null
            ? (navigation?.api ?? 'inline')
            : (dot >= 0 ? firstCall.substring(dot + 1) : firstCall),
        receiver: firstCall != null && dot >= 0
            ? firstCall.substring(0, dot)
            : 'Unknown',
        isAsync: action.isAsync,
        isNavigation: navigation != null,
        route: navigation?.isRouteName == true ? navigation!.target : null,
        targetScreen:
            navigation?.isRouteName == false ? navigation!.target : null,
        stateChange:
            action.stateChanges.isEmpty ? 'None' : action.stateChanges.first,
      ));
    }
  }
}
