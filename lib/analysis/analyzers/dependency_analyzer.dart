import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:flutterastest/parser/models/parser_result.dart';
import '../models/dependency_edge.dart';
import '../models/widget_model.dart';

enum DependencyCategory {
  application,
  framework,
  sdk,
  ui,
  callback,
  external,
}

class DependencyAnalyzer {
  const DependencyAnalyzer();

  List<DependencyEdge> analyse(
      ParserResult parserResult, List<WidgetModel> knownWidgets) {
    final Set<DependencyEdge> rawEdges = {};
    final knownWidgetNames = knownWidgets.map((w) => w.name).toSet();

    for (final unitResult in parserResult.resolvedUnits) {
      final visitor = _DependencyVisitor(knownWidgetNames);
      unitResult.unit.accept(visitor);
      rawEdges.addAll(visitor.edges);
    }

    final Map<String, DependencyEdge> deduplicated = {};

    int _getPriority(DependencyType type) {
      switch (type) {
        case DependencyType.getx:
        case DependencyType.provider:
        case DependencyType.riverpod:
        case DependencyType.bloc:
        case DependencyType.cubit:
          return 4;
        case DependencyType.constructor:
          return 3;
        case DependencyType.field:
          return 2;
        case DependencyType.modelComposition:
          return 1;
        case DependencyType.objectCreation:
          return 0;
      }
    }

    for (final edge in rawEdges) {
      final key = '${edge.from}->${edge.to}';
      if (deduplicated.containsKey(key)) {
        final existingEdge = deduplicated[key]!;
        if (_getPriority(edge.type) > _getPriority(existingEdge.type)) {
          deduplicated[key] = edge;
        }
      } else {
        deduplicated[key] = edge;
      }
    }

    return deduplicated.values.toList();
  }
}

class _DependencyVisitor extends RecursiveAstVisitor<void> {
  _DependencyVisitor(this.knownWidgetNames);

  final Set<String> knownWidgetNames;
  final Set<DependencyEdge> edges = {};
  String? currentClass;

  DependencyCategory _categorize(String type, DartType? dartType) {
    if (type.contains('Function(') ||
        type.contains('Function') ||
        type == 'VoidCallback') {
      return DependencyCategory.callback;
    }

    if (knownWidgetNames.contains(type) ||
        type.endsWith('Physics') ||
        type.endsWith('Route') ||
        type.endsWith('ThemeData')) {
      return DependencyCategory.ui;
    }

    const sdkAndExternal = {
      'String',
      'int',
      'double',
      'bool',
      'num',
      'dynamic',
      'void',
      'var',
      'List',
      'Map',
      'Set',
      'Iterable',
      'Future',
      'Stream',
      'Duration',
      'RegExp',
      'DateTime',
      'File',
      'DateFormat',
      'XFile',
      'ImagePicker',
      'ImageEditor',
      'NumberFormat',
      'MultipartBody',
    };
    if (sdkAndExternal.contains(type)) return DependencyCategory.sdk;

    // 👇 ADDED: The final missed Flutter/UI widgets from the RC1 review
    const flutterUi = {
      'Widget',
      'BuildContext',
      'Key',
      'Object',
      'State',
      'Size',
      'Color',
      'TextEditingController',
      'ScrollController',
      'AnimationController',
      'IconData',
      'TextSpan',
      'LinearGradient',
      'FileImage',
      'NetworkImage',
      'SvgPicture',
      'Scaffold',
      'AppBar',
      'IconButton',
      'Icon',
      'Text',
      'Center',
      'Padding',
      'EdgeInsets',
      'ListView',
      'Container',
      'BoxDecoration',
      'Border',
      'BorderRadius',
      'Row',
      'SizedBox',
      'Expanded',
      'Column',
      'SafeArea',
      'SingleChildScrollView',
      'TextStyle',
      'GestureDetector',
      'RefreshIndicator',
      'Align',
      'Stack',
      'Positioned',
      'Flexible',
      'Wrap',
      'RichText',
      'Image',
      'Divider',
      'Visibility',
      'CircleAvatar',
      'AnimatedContainer',
      'ListTile',
      'InkWell',
      'TextButton',
      'DraggableScrollableSheet',
      'ResponsiveRowColumnItem',
      'PageController',
      'PageView',
      'InteractiveViewer',
      'CachedNetworkImage',
      'MaterialPageRoute',
      'VideoProgressIndicator',
      'TextSelection',
      'TextPosition',
      'VideoPlayerController',
      'CustomUrlLaunchers',
      'CustomDialouges',
      'GetMaterialApp',
      'MaterialApp',
      'ScreenUtilInit',
      'GetBuilder',
      'Obx',
      'AnimatedPadding',
      'ClipRRect',
      'PreferredSize',
      'Spacer',
      'BoxShadow',
      'Offset',
      'Shadow',
      'LinearProgressIndicator',
      'AlertDialog',
      'GridView',
      'SnackBar',
      'SfPdfViewer',
    };
    if (flutterUi.contains(type)) return DependencyCategory.ui;

    // 👇 ADDED: Syncfusion package firewall
    if (dartType != null) {
      try {
        final dynamic t = dartType;
        final element = t.element2 ?? t.element;
        if (element != null) {
          final source = element.source ?? element.librarySource;
          if (source != null) {
            final uri = source.uri.toString();
            if (uri.startsWith('dart:')) return DependencyCategory.sdk;
            if (uri.startsWith('package:flutter'))
              return DependencyCategory.framework;
            if (uri.startsWith('package:cached_network_image') ||
                uri.startsWith('package:video_player') ||
                uri.startsWith('package:intl') ||
                uri.startsWith('package:image_picker') ||
                uri.startsWith('package:image_editor') ||
                uri.startsWith('package:syncfusion')) {
              return DependencyCategory.external;
            }
          }
        }
      } catch (_) {}
    }

    return DependencyCategory.application;
  }

  void _addDependency(
      DartType? dartType, String fallbackName, DependencyType type) {
    if (currentClass == null) return;

    String to = fallbackName.replaceAll('?', '');
    if (dartType != null) {
      try {
        to = dartType.getDisplayString(withNullability: false);
      } catch (_) {}
    }

    if (to.isEmpty || to == currentClass) return;
    if (to == '${currentClass}State' || to == '_${currentClass}State') return;

    final category = _categorize(to, dartType);

    if (category == DependencyCategory.application) {
      if (to.startsWith('_') || to.contains('<')) return;

      DependencyType finalType = type;
      if (type == DependencyType.objectCreation) {
        final isModel = !currentClass!.endsWith('Controller') &&
            !currentClass!.endsWith('Repo') &&
            !currentClass!.endsWith('Service') &&
            !currentClass!.endsWith('Screen') &&
            !currentClass!.endsWith('State') &&
            !currentClass!.endsWith('Widget');
        if (isModel) {
          finalType = DependencyType.modelComposition;
        }
      }

      edges.add(DependencyEdge(from: currentClass!, to: to, type: finalType));
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final previousClass = currentClass;
    currentClass = node.name.lexeme;
    super.visitClassDeclaration(node);
    currentClass = previousClass;
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    for (final param in node.parameters.parameters) {
      if (param is SimpleFormalParameter && param.type != null) {
        _addDependency(param.type!.type, param.type!.toSource(),
            DependencyType.constructor);
      }
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    final typeNode = node.fields.type;
    if (typeNode != null) {
      _addDependency(typeNode.type, typeNode.toSource(), DependencyType.field);
    }
    super.visitFieldDeclaration(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final typeNode = node.constructorName.type;
    _addDependency(
        typeNode.type, typeNode.toSource(), DependencyType.objectCreation);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    final typeArgs = node.typeArguments?.arguments;

    if (typeArgs != null && typeArgs.isNotEmpty) {
      final typeArg = typeArgs.first;
      if (methodName == 'read' || methodName == 'watch') {
        _addDependency(
            typeArg.type, typeArg.toSource(), DependencyType.provider);
      } else if (methodName == 'find' && node.target?.toSource() == 'Get') {
        _addDependency(typeArg.type, typeArg.toSource(), DependencyType.getx);
      }
    }
    super.visitMethodInvocation(node);
  }
}
