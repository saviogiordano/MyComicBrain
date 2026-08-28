import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/preferences_shared_preferences_adapter.dart';
import 'package:mycomicbrain/core/data/secure_storage.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  late SettingsRepository repo;
  late _SecureStorageInMemoria secureStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    secureStorage = _SecureStorageInMemoria();
    repo = SettingsRepository(
      preferences: SharedPreferencesAdapter(
        await SharedPreferences.getInstance(),
      ),
      secureStorage: secureStorage,
    );
  });

  test('providerAi è null finché non impostato', () {
    expect(repo.providerAi(RuoloProviderAi.visivo), isNull);
  });

  test('impostaProviderAi persiste e legge lo stesso provider', () async {
    await repo.impostaProviderAi(RuoloProviderAi.visivo, AiProvider.openRouter);
    expect(repo.providerAi(RuoloProviderAi.visivo), AiProvider.openRouter);
  });

  test('le API key AI sono isolate per provider', () async {
    await repo.impostaApiKeyAi(
      RuoloProviderAi.visivo,
      AiProvider.claude,
      'chiave-claude',
    );
    await repo.impostaApiKeyAi(
      RuoloProviderAi.visivo,
      AiProvider.openai,
      'chiave-openai',
    );

    expect(
      await repo.apiKeyAi(RuoloProviderAi.visivo, AiProvider.claude),
      'chiave-claude',
    );
    expect(
      await repo.apiKeyAi(RuoloProviderAi.visivo, AiProvider.openai),
      'chiave-openai',
    );
    expect(
      await repo.apiKeyAi(RuoloProviderAi.visivo, AiProvider.locale),
      isNull,
    );
  });

  test('impostare una API key AI a null la cancella', () async {
    await repo.impostaApiKeyAi(
      RuoloProviderAi.visivo,
      AiProvider.claude,
      'chiave-claude',
    );
    await repo.impostaApiKeyAi(RuoloProviderAi.visivo, AiProvider.claude, null);

    expect(
      await repo.apiKeyAi(RuoloProviderAi.visivo, AiProvider.claude),
      isNull,
    );
  });

  test('i modelli sono isolati per provider', () async {
    await repo.impostaModello(
      RuoloProviderAi.visivo,
      AiProvider.claude,
      'claude-opus-5',
    );
    await repo.impostaModello(
      RuoloProviderAi.visivo,
      AiProvider.openai,
      'gpt-4o',
    );

    expect(
      repo.modello(RuoloProviderAi.visivo, AiProvider.claude),
      'claude-opus-5',
    );
    expect(repo.modello(RuoloProviderAi.visivo, AiProvider.openai), 'gpt-4o');
    expect(repo.modello(RuoloProviderAi.visivo, AiProvider.locale), isNull);
  });

  test('urlLocale persiste', () async {
    expect(repo.urlLocale(RuoloProviderAi.visivo), isNull);
    await repo.impostaUrlLocale(
      RuoloProviderAi.visivo,
      'http://localhost:11434/v1',
    );
    expect(
      repo.urlLocale(RuoloProviderAi.visivo),
      'http://localhost:11434/v1',
    );
  });

  test(
    'Visivo e Testuale sono configurazioni pienamente indipendenti (#127)',
    () async {
      await repo.impostaProviderAi(RuoloProviderAi.visivo, AiProvider.claude);
      await repo.impostaProviderAi(RuoloProviderAi.testuale, AiProvider.openai);
      await repo.impostaApiKeyAi(
        RuoloProviderAi.visivo,
        AiProvider.claude,
        'chiave-visivo',
      );
      await repo.impostaApiKeyAi(
        RuoloProviderAi.testuale,
        AiProvider.claude,
        'chiave-testuale',
      );
      await repo.impostaModello(
        RuoloProviderAi.visivo,
        AiProvider.claude,
        'claude-opus-5',
      );
      await repo.impostaModello(
        RuoloProviderAi.testuale,
        AiProvider.claude,
        'claude-haiku-4-5',
      );

      expect(repo.providerAi(RuoloProviderAi.visivo), AiProvider.claude);
      expect(repo.providerAi(RuoloProviderAi.testuale), AiProvider.openai);
      expect(
        await repo.apiKeyAi(RuoloProviderAi.visivo, AiProvider.claude),
        'chiave-visivo',
      );
      expect(
        await repo.apiKeyAi(RuoloProviderAi.testuale, AiProvider.claude),
        'chiave-testuale',
      );
      expect(
        repo.modello(RuoloProviderAi.visivo, AiProvider.claude),
        'claude-opus-5',
      );
      expect(
        repo.modello(RuoloProviderAi.testuale, AiProvider.claude),
        'claude-haiku-4-5',
      );
    },
  );

  group('migraSeNecessario (#127)', () {
    test(
      'semina entrambi i ruoli a copia della config singola preesistente',
      () async {
        SharedPreferences.setMockInitialValues({
          'settings.aiProvider': AiProvider.claude.name,
          'settings.aiProvider.modello.claude': 'claude-opus-5',
          'settings.aiProvider.locale.url': 'http://localhost:11434/v1',
        });
        final secureStorage = _SecureStorageInMemoria();
        await secureStorage.write(
          'settings.aiProvider.apiKey.claude',
          'chiave-legacy',
        );
        final repo = SettingsRepository(
          preferences: SharedPreferencesAdapter(
            await SharedPreferences.getInstance(),
          ),
          secureStorage: secureStorage,
        );

        await repo.migraSeNecessario();

        for (final ruolo in RuoloProviderAi.values) {
          expect(repo.providerAi(ruolo), AiProvider.claude);
          expect(
            repo.modello(ruolo, AiProvider.claude),
            'claude-opus-5',
          );
          expect(
            await repo.apiKeyAi(ruolo, AiProvider.claude),
            'chiave-legacy',
          );
          expect(repo.urlLocale(ruolo), 'http://localhost:11434/v1');
        }
      },
    );

    test('non fa nulla se non c\'era alcuna config preesistente', () async {
      await repo.migraSeNecessario();

      expect(repo.providerAi(RuoloProviderAi.visivo), isNull);
      expect(repo.providerAi(RuoloProviderAi.testuale), isNull);
    });

    test('non sovrascrive un ruolo Visivo già seminato/configurato', () async {
      await repo.impostaProviderAi(RuoloProviderAi.visivo, AiProvider.openai);
      await repo.migraSeNecessario();

      expect(repo.providerAi(RuoloProviderAi.visivo), AiProvider.openai);
      expect(repo.providerAi(RuoloProviderAi.testuale), isNull);
    });
  });

  test(
    'apiKeyComics è uno scalare singolo indipendente dalle API key AI',
    () async {
      await repo.impostaApiKeyComics('chiave-comicvine');
      await repo.impostaApiKeyAi(
        RuoloProviderAi.visivo,
        AiProvider.claude,
        'chiave-claude',
      );

      expect(await repo.apiKeyComics, 'chiave-comicvine');
      expect(
        await repo.apiKeyAi(RuoloProviderAi.visivo, AiProvider.claude),
        'chiave-claude',
      );
    },
  );

  test('impostare apiKeyComics a stringa vuota la cancella', () async {
    await repo.impostaApiKeyComics('chiave-comicvine');
    await repo.impostaApiKeyComics('');

    expect(await repo.apiKeyComics, isNull);
  });
}
