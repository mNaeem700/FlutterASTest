import '../../analysis/models/callback_model.dart';

class CallbackFormatter {
  String format(String screenName, List<CallbackModel> callbacks,
      String widgetTreeText, List<String> screenDeps) {
    final buffer = StringBuffer();
    buffer.writeln('Callbacks\n');

    final filtered = callbacks
        .where((cb) {
          return screenDeps.contains(cb.receiver) ||
              widgetTreeText.contains(cb.widgetName) ||
              cb.widgetName == screenName;
        })
        .take(6)
        .toList();

    if (filtered.isEmpty) return 'Callbacks\n\nNone';

    for (final cb in filtered) {
      buffer.writeln('${cb.widgetName}.${cb.callbackName}');
      if (cb.receiver != 'Unknown' && cb.receiver.isNotEmpty) {
        buffer.writeln('→ ${cb.receiver}.${cb.invokedMethod}\n');
      } else {
        buffer.writeln('→ ${cb.invokedMethod}\n');
      }
    }
    return buffer.toString().trim();
  }
}
