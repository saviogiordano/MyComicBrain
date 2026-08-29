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

  static const _chiaveApiKeyComics = 'settings.comics.apiKey';

  // --- Chiavi pre-split (#127): un solo scalare/mappa condiviso da tutte le
  // chiamate AI, senza distinzione di ruolo. Lette solo da
  // `migraSeNecessario` per seminare le chiavi per-ruolo sotto — mai più
  // scritte dopo la migrazione.
  static const _chiaveProviderAiLegacy = 'settings.aiProvider';
  static const _chiaveUrlLocaleLegacy = 'settings.aiProvider.locale.url';
  static const _prefissoModelloLegacy = 'settings.aiProvider.modello.';
  static const _prefissoApiKeyAiLegacy = 'settings.aiProvider.apiKey.';

  // --- Chiavi per-ruolo (ADR-0001, #127): Visivo (Analisi Copertina) e
  // Testuale (Assistente) hanno ciascuno la propria selezione di brand, API
  // key, modello e URL — indipendenti anche a parità di brand. ---

  String _chiaveProviderAi(RuoloProviderAi ruolo) =>
      'settings.aiProvider.${ruolo.name}';

  String _chiaveApiKeyAi(RuoloProviderAi ruolo, AiProvider provider) =>
      'settings.aiProvider.apiKey.${ruolo.name}.${provider.name}';

  String _chiaveModello(RuoloProviderAi ruolo, AiProvider provider) =>
      'settings.aiProvider.modello.${ruolo.name}.${provider.name}';

  String _chiaveUrlLocale(RuoloProviderAi ruolo) =>
      'settings.aiProvider.locale.url.${ruolo.name}';

  // --- Provider AI selezionato per ruolo (non sensibile) ---

  /// Il provider AI attualmente selezionato per [ruolo], `null` se l'utente
  /// non ha ancora scelto (nessun default forzato: lo decide la UI di #107).
  AiProvider? providerAi(RuoloProviderAi ruolo) {
    final raw = _preferences.getString(_chiaveProviderAi(ruolo));
    if (raw == null) return null;
    return AiProvider.values.asNameMap()[raw];
  }

  Future<void> impostaProviderAi(RuoloProviderAi ruolo, AiProvider provider) {
    return _preferences.setString(_chiaveProviderAi(ruolo), provider.name);
  }

  // --- API key per (ruolo, provider AI), sensibile ---

  Future<String?> apiKeyAi(RuoloProviderAi ruolo, AiProvider provider) {
    return _secureStorage.read(_chiaveApiKeyAi(ruolo, provider));
  }

  /// `null` o stringa vuota cancella la chiave salvata per [ruolo]/[provider].
  Future<void> impostaApiKeyAi(
    RuoloProviderAi ruolo,
    AiProvider provider,
    String? apiKey,
  ) {
    return _secureStorage.write(_chiaveApiKeyAi(ruolo, provider), apiKey);
  }

  // --- Modello selezionato per (ruolo, provider AI), non sensibile ---

  String? modello(RuoloProviderAi ruolo, AiProvider provider) {
    return _preferences.getString(_chiaveModello(ruolo, provider));
  }

  Future<void> impostaModello(
    RuoloProviderAi ruolo,
    AiProvider provider,
    String modello,
  ) {
    return _preferences.setString(_chiaveModello(ruolo, provider), modello);
  }

  // --- URL del provider locale per ruolo (non sensibile, usato solo quando
  // `AiProvider.locale.richiedeUrl`) ---

  String? urlLocale(RuoloProviderAi ruolo) {
    return _preferences.getString(_chiaveUrlLocale(ruolo));
  }

  Future<void> impostaUrlLocale(RuoloProviderAi ruolo, String url) {
    return _preferences.setString(_chiaveUrlLocale(ruolo), url);
  }

  /// `true` se [ruolo] ha i dati minimi per tentare una chiamata AI (§12,
  /// deciso su
  /// [UX quando il Provider AI Testuale non è configurato](https://github.com/saviogiordano/MyComicBrain/issues/123)):
  /// un provider selezionato, e il suo campo obbligatorio non vuoto — API
  /// key per i brand cloud, URL per Locale. Non verifica la raggiungibilità
  /// reale (chiave non valida, endpoint irraggiungibile): quella resta
  /// terreno di [Gestione errori dell'Assistente](https://github.com/saviogiordano/MyComicBrain/issues/124),
  /// scoperta solo al momento della chiamata.
  Future<bool> configurato(RuoloProviderAi ruolo) async {
    final provider = providerAi(ruolo);
    if (provider == null) return false;
    if (provider.richiedeUrl) {
      final url = urlLocale(ruolo);
      return url != null && url.isNotEmpty;
    }
    final apiKey = await apiKeyAi(ruolo, provider);
    return apiKey != null && apiKey.isNotEmpty;
  }

  /// Semina entrambi i ruoli (Visivo/Testuale) dalla configurazione singola
  /// preesistente al primo avvio dopo lo split (ADR-0001, deciso su #127):
  /// se l'utente aveva già configurato un provider, entrambe le selezioni
  /// partono come copia esatta di quella — l'Analisi Copertina continua a
  /// funzionare senza reconfigurazione, l'Assistente è utilizzabile da
  /// subito con la stessa config, modificabile poi indipendentemente.
  /// Rilevata dall'assenza della chiave del ruolo Visivo: se già presente,
  /// la migrazione è già avvenuta (no-op). Se l'utente non aveva mai
  /// configurato nulla (nessuna chiave legacy), no-op silenzioso: entrambi i
  /// ruoli restano semplicemente non configurati. Le chiavi legacy non
  /// vengono cancellate (dati orfani innocui, mai più letti da nessun altro
  /// metodo). Lanciata `unawaited` da `settingsRepositoryProvider`, stesso
  /// pattern di `ComicsRepository.unisciSerieDuplicate` (#58).
  Future<void> migraSeNecessario() async {
    if (providerAi(RuoloProviderAi.visivo) != null) return;

    final raw = _preferences.getString(_chiaveProviderAiLegacy);
    final providerLegacy = raw == null
        ? null
        : AiProvider.values.asNameMap()[raw];
    if (providerLegacy == null) return;

    final urlLegacy = _preferences.getString(_chiaveUrlLocaleLegacy);

    for (final ruolo in RuoloProviderAi.values) {
      await impostaProviderAi(ruolo, providerLegacy);
      for (final provider in AiProvider.values) {
        final apiKeyLegacy = await _secureStorage.read(
          '$_prefissoApiKeyAiLegacy${provider.name}',
        );
        if (apiKeyLegacy != null && apiKeyLegacy.isNotEmpty) {
          await impostaApiKeyAi(ruolo, provider, apiKeyLegacy);
        }
        final modelloLegacy = _preferences.getString(
          '$_prefissoModelloLegacy${provider.name}',
        );
        if (modelloLegacy != null) {
          await impostaModello(ruolo, provider, modelloLegacy);
        }
      }
      if (urlLegacy != null) {
        await impostaUrlLocale(ruolo, urlLegacy);
      }
    }
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
