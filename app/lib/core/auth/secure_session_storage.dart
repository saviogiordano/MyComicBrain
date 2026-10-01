import 'package:mycomicbrain/core/data/secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persiste la sessione Supabase nello storage sicuro (Keychain/Keystore)
/// invece che in chiaro in SharedPreferences, default di `supabase_flutter`
/// (#168 §4).
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage(this._storage);

  final SecureStorage _storage;

  static const _chiave = 'supabase.session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => await _storage.read(_chiave) != null;

  @override
  Future<String?> accessToken() => _storage.read(_chiave);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(_chiave, persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.write(_chiave, null);
}
