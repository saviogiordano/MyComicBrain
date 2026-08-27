import 'package:shared_preferences/shared_preferences.dart';

/// Seam su `SharedPreferences`, stesso pattern di `SecureStorage`
/// (`secure_storage.dart`): isola `SettingsRepository` dal plugin concreto
/// così chi non gira dentro un binding Flutter (es. gli script
/// `tool/verify_*.dart`, eseguiti con `dart run`, o `SettingsRepository.inMemoria`
/// usato dai test) può fornire un'implementazione che non passa per un
/// platform channel.
abstract interface class Preferences {
  String? getString(String key);
  Future<void> setString(String key, String value);
}

class SharedPreferencesAdapter implements Preferences {
  const SharedPreferencesAdapter(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}
