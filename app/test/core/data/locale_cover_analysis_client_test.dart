import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/locale_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';

/// `http.Client` finto: risponde con [risposta]/[statusCode] fissi e
/// registra l'ultima richiesta inviata, senza rete reale.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.statusCode, required this.risposta});

  final int statusCode;
  final String risposta;
  http.BaseRequest? ultimaRichiesta;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    ultimaRichiesta = request;
    return http.StreamedResponse(
      Stream.value(utf8.encode(risposta)),
      statusCode,
    );
  }
}

String _rispostaChatCompletions(Map<String, dynamic> campi) => jsonEncode({
  'choices': [
    {
      'message': {
        'role': 'assistant',
        'content': jsonEncode(campi),
        'refusal': null,
      },
    },
  ],
});

String _rispostaRifiuto(String motivo) => jsonEncode({
  'choices': [
    {
      'message': {'role': 'assistant', 'content': null, 'refusal': motivo},
    },
  ],
});

Future<SettingsRepository> _settingsConUrlEModello({String? apiKey}) async {
  final settings = SettingsRepository.inMemoria();
  await settings.impostaUrlLocale('http://localhost:11434/v1');
  await settings.impostaModello(AiProvider.locale, 'llama3');
  if (apiKey != null) {
    await settings.impostaApiKeyAi(AiProvider.locale, apiKey);
  }
  return settings;
}

const Map<String, dynamic> _campiCompleti = {
  'title': 'Amazing Spider-Man',
  'issueNumberLabel': '300',
  'publisher': 'Marvel',
  'seriesName': 'The Amazing Spider-Man',
  'authors': <String>['David Michelinie'],
  'isbn': null,
  'barcode': '076194130132500111',
  'price': '€ 1,50',
  'identifierCodes': <String>[],
  'textElements': <Map<String, dynamic>>[],
  'characters': <String>['Spider-Man', 'Venom'],
  'coverStyleTags': <String>['stile realistico'],
  'visualElementTags': <String>['sfondo con esplosione'],
  'recognizedPublisherLogo': 'Marvel',
  'recognizedSeriesLogo': null,
  'printingType': 'Direct Edition',
  'classificazione': 'Rated T+',
  'description': 'Peter Parker affronta Venom in un confronto decisivo.',
};

void main() {
  test(
    'estrae i campi grezzi da una risposta 200 conforme allo schema, senza API key',
    () async {
      final fake = _FakeHttpClient(
        statusCode: 200,
        risposta: _rispostaChatCompletions(_campiCompleti),
      );
      final client = LocaleCoverAnalysisClient(
        settingsRepository: await _settingsConUrlEModello(),
        httpClient: fake,
      );

      final risultato = await client.estraiCopertina(Uint8List(0));

      expect(risultato.title, 'Amazing Spider-Man');
      expect(risultato.characters, ['Spider-Man', 'Venom']);
      expect(risultato.description, isNotNull);
      expect(
        fake.ultimaRichiesta!.url.toString(),
        'http://localhost:11434/v1/chat/completions',
      );
      expect(
        fake.ultimaRichiesta!.headers.containsKey('Authorization'),
        isFalse,
      );
    },
  );

  test(
    "include l'header Authorization quando l'API key è impostata",
    () async {
      final fake = _FakeHttpClient(
        statusCode: 200,
        risposta: _rispostaChatCompletions(_campiCompleti),
      );
      final client = LocaleCoverAnalysisClient(
        settingsRepository: await _settingsConUrlEModello(
          apiKey: 'chiave-test',
        ),
        httpClient: fake,
      );

      await client.estraiCopertina(Uint8List(0));

      expect(
        fake.ultimaRichiesta!.headers['Authorization'],
        'Bearer chiave-test',
      );
    },
  );

  test("normalizza uno slash finale nell'URL configurato", () async {
    final settings = SettingsRepository.inMemoria();
    await settings.impostaUrlLocale('http://localhost:11434/v1/');
    await settings.impostaModello(AiProvider.locale, 'llama3');
    final fake = _FakeHttpClient(
      statusCode: 200,
      risposta: _rispostaChatCompletions(_campiCompleti),
    );
    final client = LocaleCoverAnalysisClient(
      settingsRepository: settings,
      httpClient: fake,
    );

    await client.estraiCopertina(Uint8List(0));

    expect(
      fake.ultimaRichiesta!.url.toString(),
      'http://localhost:11434/v1/chat/completions',
    );
  });

  test("un campo non trovato resta null, non genera un'eccezione", () async {
    final campi = Map<String, dynamic>.from(_campiCompleti)
      ..['title'] = null
      ..['publisher'] = null
      ..['printingType'] = null
      ..['classificazione'] = null
      ..['description'] = null;
    final client = LocaleCoverAnalysisClient(
      settingsRepository: await _settingsConUrlEModello(),
      httpClient: _FakeHttpClient(
        statusCode: 200,
        risposta: _rispostaChatCompletions(campi),
      ),
    );

    final risultato = await client.estraiCopertina(Uint8List(0));

    expect(risultato.title, isNull);
    expect(risultato.publisher, isNull);
    expect(risultato.printingType, isNull);
    expect(risultato.classificazione, isNull);
    expect(risultato.description, isNull);
  });

  test(
    'un rifiuto del modello (campo refusal) solleva CoverAnalysisException con il motivo',
    () async {
      final client = LocaleCoverAnalysisClient(
        settingsRepository: await _settingsConUrlEModello(),
        httpClient: _FakeHttpClient(
          statusCode: 200,
          risposta: _rispostaRifiuto(
            'non posso identificare persone reali in una foto',
          ),
        ),
      );

      await expectLater(
        () => client.estraiCopertina(Uint8List(0)),
        throwsA(
          isA<CoverAnalysisException>().having(
            (e) => e.message,
            'message',
            contains('non posso identificare persone reali'),
          ),
        ),
      );
    },
  );

  test('una risposta HTTP non-2xx solleva CoverAnalysisException', () async {
    final client = LocaleCoverAnalysisClient(
      settingsRepository: await _settingsConUrlEModello(),
      httpClient: _FakeHttpClient(statusCode: 500, risposta: 'errore interno'),
    );

    await expectLater(
      () => client.estraiCopertina(Uint8List(0)),
      throwsA(isA<CoverAnalysisException>()),
    );
  });

  test(
    'senza URL configurato nelle Impostazioni solleva CoverAnalysisException senza chiamare la rete',
    () async {
      final settings = SettingsRepository.inMemoria();
      await settings.impostaModello(AiProvider.locale, 'llama3');
      final fake = _FakeHttpClient(
        statusCode: 200,
        risposta: _rispostaChatCompletions(_campiCompleti),
      );
      final client = LocaleCoverAnalysisClient(
        settingsRepository: settings,
        httpClient: fake,
      );

      await expectLater(
        () => client.estraiCopertina(Uint8List(0)),
        throwsA(isA<CoverAnalysisException>()),
      );
      expect(fake.ultimaRichiesta, isNull);
    },
  );

  test(
    'senza modello configurato nelle Impostazioni solleva CoverAnalysisException senza chiamare la rete',
    () async {
      final settings = SettingsRepository.inMemoria();
      await settings.impostaUrlLocale('http://localhost:11434/v1');
      final fake = _FakeHttpClient(
        statusCode: 200,
        risposta: _rispostaChatCompletions(_campiCompleti),
      );
      final client = LocaleCoverAnalysisClient(
        settingsRepository: settings,
        httpClient: fake,
      );

      await expectLater(
        () => client.estraiCopertina(Uint8List(0)),
        throwsA(isA<CoverAnalysisException>()),
      );
      expect(fake.ultimaRichiesta, isNull);
    },
  );

  group('verificaConnessione (#108)', () {
    test('con risposta 200 non solleva nulla', () async {
      final client = LocaleCoverAnalysisClient(
        settingsRepository: await _settingsConUrlEModello(),
        httpClient: _FakeHttpClient(statusCode: 200, risposta: '{}'),
      );

      await client.verificaConnessione();
    });

    test('con risposta non-200 solleva CoverAnalysisException', () async {
      final client = LocaleCoverAnalysisClient(
        settingsRepository: await _settingsConUrlEModello(),
        httpClient: _FakeHttpClient(
          statusCode: 500,
          risposta: '{"error": "model not found"}',
        ),
      );

      await expectLater(
        client.verificaConnessione,
        throwsA(isA<CoverAnalysisException>()),
      );
    });

    test(
      'senza URL configurato solleva un errore di configurazione mancante, senza chiamare la rete',
      () async {
        final settings = SettingsRepository.inMemoria();
        await settings.impostaModello(AiProvider.locale, 'llama3');
        final fake = _FakeHttpClient(statusCode: 200, risposta: '{}');
        final client = LocaleCoverAnalysisClient(
          settingsRepository: settings,
          httpClient: fake,
        );

        await expectLater(
          client.verificaConnessione,
          throwsA(isA<CoverAnalysisException>()),
        );
        expect(fake.ultimaRichiesta, isNull);
      },
    );
  });
}
