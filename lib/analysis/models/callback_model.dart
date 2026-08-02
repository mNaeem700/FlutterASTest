class CallbackModel {
  final String widgetName;
  final String callbackName;
  final String invokedMethod;
  final String receiver;
  final bool isAsync;
  final bool isNavigation;
  final String? route; // 👈 Ensure this property is defined
  final String? targetScreen; // 👈 Optional alias if using targetScreen
  final String stateChange;

  const CallbackModel({
    required this.widgetName,
    required this.callbackName,
    required this.invokedMethod,
    required this.receiver,
    required this.isAsync,
    required this.isNavigation,
    this.route,
    this.targetScreen,
    required this.stateChange,
  });

  Map<String, dynamic> toJson() => {
        'widgetName': widgetName,
        'callbackName': callbackName,
        'invokedMethod': invokedMethod,
        'receiver': receiver,
        'isAsync': isAsync,
        'isNavigation': isNavigation,
        'route': route,
        'targetScreen': targetScreen,
        'stateChange': stateChange,
      };
}
