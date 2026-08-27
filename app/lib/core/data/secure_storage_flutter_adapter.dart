import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mycomicbrain/core/data/secure_storage.dart';

/// Implementazione di [SecureStorage] su `flutter_secure_storage` — in un
/// file separato da `secure_storage.dart` perché il plugin richiede
/// `package:flutter`, non disponibile fuori da un binding Flutter (vedi il
/// commento su [SecureStorage]). Usata solo dal wiring dell'app
/// (`providers.dart`).
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
