import '../../analysis/models/callback_model.dart';

class NavigationFormatter {
  String format(
      String screenName, List<CallbackModel> callbacks, String widgetTreeText) {
    final buffer = StringBuffer();
    buffer.writeln('Navigation\n');
    bool hasNav = false;

    for (final cb in callbacks) {
      if (cb.isNavigation &&
          (widgetTreeText.contains(cb.widgetName) ||
              cb.widgetName == screenName)) {
        hasNav = true;
        String target = cb.route ?? cb.targetScreen ?? 'Previous Screen';
        if (cb.invokedMethod.contains('pop') ||
            cb.invokedMethod.contains('back')) {
          target = 'Back';
        }

        // e.g. Back -> HomeScreen
        buffer.writeln(cb.invokedMethod.contains('pop') ? 'Back' : 'Success');
        buffer.writeln('→ $target\n');
      }
    }

    if (!hasNav) return 'Navigation\n\nNone';
    return buffer.toString().trim();
  }
}
