import 'package:mycomicbrain/core/data/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Implementazione di [Preferences] su `shared_preferences` — in un file
/// separato da `preferences.dart` perché il plugin richiede
/// `package:flutter`, non disponibile fuori da un binding Flutter (vedi il
/// commento su [Preferences]). Usata solo dal wiring dell'app
/// (`providers.dart`).
class SharedPreferencesAdapter implements Preferences {
  const SharedPreferencesAdapter(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}
