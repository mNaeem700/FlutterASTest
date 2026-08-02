import '../../analysis/models/state_model.dart';

class StateFormatter {
  String format(List<dynamic> states, List<String> screenDependencies) {
    final buffer = StringBuffer();
    buffer.writeln('State\n');
    bool hasState = false;

    for (final stateObj in states) {
      if (stateObj is StateModel &&
          screenDependencies.contains(stateObj.className)) {
        hasState = true;
        buffer.writeln(stateObj.className);
        buffer.writeln('\nVariables\n');

        for (final v in stateObj.variables) {
          buffer.writeln(v.name);
        }
        buffer.writeln();
      }
    }

    if (!hasState) return 'State\n\nNone';
    return buffer.toString().trim();
  }
}
