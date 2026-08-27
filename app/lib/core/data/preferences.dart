/// Seam su un backend di preferenze semplici (chiave→stringa), stesso
/// pattern di `SecureStorage` (`secure_storage.dart`): isola
/// `SettingsRepository` dal plugin concreto così chi non gira dentro un
/// binding Flutter (es. gli script `tool/verify_*.dart`,
/// `tool/analyze_cover.dart`, eseguiti con `dart run`, o
/// `SettingsRepository.inMemoria` usato dai test) può fornire
/// un'implementazione che non passa per un platform channel. Nessuna
/// dipendenza da `package:flutter` in questo file — l'implementazione
/// concreta (`SharedPreferencesAdapter`, che la richiede) vive in
/// `preferences_shared_preferences_adapter.dart`.
abstract interface class Preferences {
  String? getString(String key);
  Future<void> setString(String key, String value);
}
