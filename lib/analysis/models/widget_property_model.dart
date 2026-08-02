class WidgetPropertyModel {
  final String widgetName;
  final String propertyName;
  final String valueType;
  final String category;

  const WidgetPropertyModel({
    required this.widgetName,
    required this.propertyName,
    required this.valueType,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
        'widgetName': widgetName,
        'propertyName': propertyName,
        'valueType': valueType,
        'category': category,
      };
}
