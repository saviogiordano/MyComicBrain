import 'package:flutter_test/flutter_test.dart';
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
      preferences: await SharedPreferences.getInstance(),
      secureStorage: secureStorage,
    );
  });

  test('providerAi è null finché non impostato', () {
    expect(repo.providerAi, isNull);
  });

  test('impostaProviderAi persiste e legge lo stesso provider', () async {
    await repo.impostaProviderAi(AiProvider.openRouter);
    expect(repo.providerAi, AiProvider.openRouter);
  });

  test('le API key AI sono isolate per provider', () async {
    await repo.impostaApiKeyAi(AiProvider.claude, 'chiave-claude');
    await repo.impostaApiKeyAi(AiProvider.openai, 'chiave-openai');

    expect(await repo.apiKeyAi(AiProvider.claude), 'chiave-claude');
    expect(await repo.apiKeyAi(AiProvider.openai), 'chiave-openai');
    expect(await repo.apiKeyAi(AiProvider.locale), isNull);
  });

  test('impostare una API key AI a null la cancella', () async {
    await repo.impostaApiKeyAi(AiProvider.claude, 'chiave-claude');
    await repo.impostaApiKeyAi(AiProvider.claude, null);

    expect(await repo.apiKeyAi(AiProvider.claude), isNull);
  });

  test('i modelli sono isolati per provider', () async {
    await repo.impostaModello(AiProvider.claude, 'claude-opus-5');
    await repo.impostaModello(AiProvider.openai, 'gpt-4o');

    expect(repo.modello(AiProvider.claude), 'claude-opus-5');
    expect(repo.modello(AiProvider.openai), 'gpt-4o');
    expect(repo.modello(AiProvider.locale), isNull);
  });

  test('urlLocale persiste', () async {
    expect(repo.urlLocale, isNull);
    await repo.impostaUrlLocale('http://localhost:11434/v1');
    expect(repo.urlLocale, 'http://localhost:11434/v1');
  });

  test('apiKeyComics è uno scalare singolo indipendente dalle API key AI', () async {
    await repo.impostaApiKeyComics('chiave-comicvine');
    await repo.impostaApiKeyAi(AiProvider.claude, 'chiave-claude');

    expect(await repo.apiKeyComics, 'chiave-comicvine');
    expect(await repo.apiKeyAi(AiProvider.claude), 'chiave-claude');
  });

  test('impostare apiKeyComics a stringa vuota la cancella', () async {
    await repo.impostaApiKeyComics('chiave-comicvine');
    await repo.impostaApiKeyComics('');

    expect(await repo.apiKeyComics, isNull);
  });
}
