import 'package:meta/meta.dart';

@immutable
class WidgetModel {
  const WidgetModel({
    required this.name,
    required this.filePath,
    required this.isStateful,
    required this.isStateless,
  });

  final String name;
  final String filePath;
  final bool isStateful;
  final bool isStateless;
}
