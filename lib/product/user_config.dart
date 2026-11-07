import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Settings of one developer, in `~/.flutterastest/config.json`: default
/// provider and model, their own API keys, and which cloud providers they
/// agreed to send code to. `FLUTTERASTEST_HOME` moves the folder.
class UserConfig {
  UserConfig._(this.file, this._data);

  final File file;
  final Map<String, dynamic> _data;

  /// Settings a developer may set with `flutterastest config set`.
  static const settings = {'provider', 'model', 'baseUrl'};

  factory UserConfig.load({String? home}) {
    final file = File(p.join(home ?? defaultHome(), 'config.json'));
    var data = <String, dynamic>{};
    if (file.existsSync()) {
      try {
        data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } on FormatException {
        stderr.writeln('Warning: ignoring unreadable settings file ${file.path}');
      }
    }
    return UserConfig._(file, data);
  }

  static String defaultHome() {
    final env = Platform.environment;
    return env['FLUTTERASTEST_HOME'] ??
        p.join(env['HOME'] ?? env['USERPROFILE'] ?? '.', '.flutterastest');
  }

  String? operator [](String key) => _data[key] as String?;

  void operator []=(String key, String? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    _save();
  }

  String? apiKey(String provider) => (_data['apiKeys'] as Map?)?[provider] as String?;

  void setApiKey(String provider, String? key) {
    final keys = Map<String, dynamic>.from((_data['apiKeys'] as Map?) ?? const {});
    if (key == null) {
      keys.remove(provider);
    } else {
      keys[provider] = key;
    }
    _data['apiKeys'] = keys;
    _save();
  }

  bool cloudConsent(String provider) =>
      ((_data['cloudConsent'] as Map?)?[provider] as bool?) ?? false;

  void setCloudConsent(String provider, bool value) {
    final consent = Map<String, dynamic>.from((_data['cloudConsent'] as Map?) ?? const {});
    consent[provider] = value;
    _data['cloudConsent'] = consent;
    _save();
  }

  /// The settings for display, with API keys masked.
  Map<String, String> describe() => {
        for (final key in settings)
          if (this[key] != null) key: this[key]!,
        for (final entry in ((_data['apiKeys'] as Map?) ?? const {}).entries)
          'apiKey.${entry.key}': mask('${entry.value}'),
        for (final entry in ((_data['cloudConsent'] as Map?) ?? const {}).entries)
          'cloudConsent.${entry.key}': '${entry.value}',
      };

  static String mask(String key) =>
      key.length <= 8 ? '****' : '${key.substring(0, 4)}****${key.substring(key.length - 2)}';

  void _save() {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_data));
    // The file holds API keys. On Windows the user profile folder is private.
    if (!Platform.isWindows) Process.runSync('chmod', ['600', file.path]);
  }
}
