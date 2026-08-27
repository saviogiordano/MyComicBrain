/// Seam su un backend di storage sicuro (Keychain su iOS, Keystore-backed
/// EncryptedSharedPreferences su Android — deciso su
/// [Persistenza e sicurezza delle impostazioni](https://github.com/saviogiordano/MyComicBrain/issues/101)):
/// isola `SettingsRepository` dal plugin concreto così i test possono
/// sostituirlo con un fake in memoria invece di passare per un platform
/// channel. Nessuna dipendenza da `package:flutter` in questo file —
/// l'implementazione concreta (`FlutterSecureStorageAdapter`, che la
/// richiede) vive in `secure_storage_flutter_adapter.dart`, così
/// `SettingsRepository` resta costruibile con `dart run` (script
/// `tool/verify_*.dart`, `tool/analyze_cover.dart`) fuori da un binding
/// Flutter.
abstract interface class SecureStorage {
  Future<String?> read(String key);

  /// `null` cancella la chiave invece di scrivere una stringa vuota.
  Future<void> write(String key, String? value);
}
