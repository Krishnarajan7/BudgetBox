import '../api_client.dart';
import 'wire.dart';

/// The small preferences the whole box reads: name, currency, salary day, the
/// theme. A flat string map on purpose — a new setting needs no migration on
/// either side, and the meaning of each key lives with the screen that uses it.
class SettingsApi {
  const SettingsApi(this._c);

  final BbxClient _c;

  Future<Map<String, String>> all() async =>
      wireStringMap(await _c.get('/v1/settings'));

  /// Returns the whole map back, so a write and a refresh are one call.
  Future<Map<String, String>> set(String key, String value) async =>
      wireStringMap(await _c.put('/v1/settings/$key', SettingIn(value).toJson()));
}

class SettingIn {
  const SettingIn(this.value);

  final String value;

  Map<String, dynamic> toJson() => {'value': value};
}
