import 'package:mycomicbrain/core/data/preferences.dart';
import 'package:mycomicbrain/core/data/secure_storage.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';

/// Unico punto di accesso alle Impostazioni (§12, schema deciso su
/// [Persistenza e sicurezza delle impostazioni](https://github.com/saviogiordano/MyComicBrain/issues/101)):
/// instrada i campi sensibili (API key) a [SecureStorage] e quelli non
/// sensibili a [Preferences]. I chiamanti (schermo Impostazioni #107, client
/// AI/ComicVine migrati su #106) non sanno dove vive fisicamente ciascun
/// campo.
class SettingsRepository {
  SettingsRepository({
    required Preferences preferences,
    required SecureStorage secureStorage,
  }) : _preferences = preferences,
       _secureStorage = secureStorage;

  /// Repository in memoria, senza alcun plugin Flutter dietro — per i test
  /// e per gli script `tool/verify_*.dart`, eseguiti con `dart run` fuori da
  /// un binding Flutter (dove `SharedPreferences`/`flutter_secure_storage`
  /// non funzionerebbero, essendo backed da platform channel).
  factory SettingsRepository.inMemoria() {
    return SettingsRepository(
      preferences: _PreferenzeInMemoria(),
      secureStorage: _SecureStorageInMemoria(),
    );
  }

  final Preferences _preferences;
  final SecureStorage _secureStorage;

  static const _chiaveProviderAi = 'settings.aiProvider';
  static const _chiaveUrlLocale = 'settings.aiProvider.locale.url';
  static const _prefissoModello = 'settings.aiProvider.modello.';
  static const _prefissoApiKeyAi = 'settings.aiProvider.apiKey.';
  static const _chiaveApiKeyComics = 'settings.comics.apiKey';

  // --- Provider AI selezionato (non sensibile) ---

  /// Il provider AI attualmente selezionato, `null` se l'utente non ha
  /// ancora scelto (nessun default forzato: lo decide la UI di #107).
  AiProvider? get providerAi {
    final raw = _preferences.getString(_chiaveProviderAi);
    if (raw == null) return null;
    return AiProvider.values.asNameMap()[raw];
  }

  Future<void> impostaProviderAi(AiProvider provider) {
    return _preferences.setString(_chiaveProviderAi, provider.name);
  }

  // --- API key per provider AI (mappa provider→key, sensibile) ---

  Future<String?> apiKeyAi(AiProvider provider) {
    return _secureStorage.read('$_prefissoApiKeyAi${provider.name}');
  }

  /// `null` o stringa vuota cancella la chiave salvata per [provider].
  Future<void> impostaApiKeyAi(AiProvider provider, String? apiKey) {
    return _secureStorage.write('$_prefissoApiKeyAi${provider.name}', apiKey);
  }

  // --- Modello selezionato per provider AI (mappa provider→modello, non
  // sensibile) ---

  String? modello(AiProvider provider) {
    return _preferences.getString('$_prefissoModello${provider.name}');
  }

  Future<void> impostaModello(AiProvider provider, String modello) {
    return _preferences.setString(
      '$_prefissoModello${provider.name}',
      modello,
    );
  }

  // --- URL del provider locale (non sensibile, usato solo quando
  // `AiProvider.locale.richiedeUrl`) ---

  String? get urlLocale => _preferences.getString(_chiaveUrlLocale);

  Future<void> impostaUrlLocale(String url) {
    return _preferences.setString(_chiaveUrlLocale, url);
  }

  // --- API key del provider database fumetti (scalare singolo: un solo
  // provider implementato, ComicVine — §6.4, sensibile) ---

  Future<String?> get apiKeyComics => _secureStorage.read(_chiaveApiKeyComics);

  /// `null` o stringa vuota cancella la chiave salvata.
  Future<void> impostaApiKeyComics(String? apiKey) {
    return _secureStorage.write(_chiaveApiKeyComics, apiKey);
  }
}

class _PreferenzeInMemoria implements Preferences {
  final Map<String, String> _valori = {};

  @override
  String? getString(String key) => _valori[key];

  @override
  Future<void> setString(String key, String value) async =>
      _valori[key] = value;
}

class _SecureStorageInMemoria implements SecureStorage {
  final Map<String, String> _valori = {};

  @override
  Future<String?> read(String key) async => _valori[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      _valori.remove(key);
    } else {
      _valori[key] = value;
    }
  }
}
