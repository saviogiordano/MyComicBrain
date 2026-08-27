import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Seam su `flutter_secure_storage` (Keychain su iOS, Keystore-backed
/// EncryptedSharedPreferences su Android — deciso su
/// [Persistenza e sicurezza delle impostazioni](https://github.com/saviogiordano/MyComicBrain/issues/101)):
/// isola `SettingsRepository` dal plugin concreto così i test possono
/// sostituirlo con un fake in memoria invece di passare per un platform
/// channel.
abstract interface class SecureStorage {
  Future<String?> read(String key);

  /// `null` cancella la chiave invece di scrivere una stringa vuota.
  Future<void> write(String key, String? value);
}

class FlutterSecureStorageAdapter implements SecureStorage {
  const FlutterSecureStorageAdapter([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) {
    if (value == null || value.isEmpty) {
      return _storage.delete(key: key);
    }
    return _storage.write(key: key, value: value);
  }
}
