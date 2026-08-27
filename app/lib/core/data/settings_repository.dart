import 'package:mycomicbrain/core/data/secure_storage.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unico punto di accesso alle Impostazioni (§12, schema deciso su
/// [Persistenza e sicurezza delle impostazioni](https://github.com/saviogiordano/MyComicBrain/issues/101)):
/// instrada i campi sensibili (API key) a [SecureStorage] e quelli non
/// sensibili a `SharedPreferences`. I chiamanti (schermo Impostazioni #107,
/// client AI/ComicVine migrati su #106) non sanno dove vive fisicamente
/// ciascun campo.
class SettingsRepository {
  SettingsRepository({
    required SharedPreferences preferences,
    SecureStorage secureStorage = const FlutterSecureStorageAdapter(),
  }) : _preferences = preferences,
       _secureStorage = secureStorage;

  final SharedPreferences _preferences;
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
