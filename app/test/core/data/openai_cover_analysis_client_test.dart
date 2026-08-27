import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/openai_cover_analysis_client.dart';
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

String _rispostaOpenAi(Map<String, dynamic> campi) => jsonEncode({
  'output': [
    {
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': jsonEncode(campi)},
      ],
    },
  ],
});

String _rispostaRifiuto(String motivo) => jsonEncode({
  'output': [
    {
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'refusal', 'refusal': motivo},
      ],
    },
  ],
});

Future<SettingsRepository> _settingsConApiKey() async {
  final settings = SettingsRepository.inMemoria();
  await settings.impostaApiKeyAi(AiProvider.openai, 'chiave-test');
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
    'estrae i campi grezzi da una risposta 200 conforme allo schema',
    () async {
      final client = OpenAiCoverAnalysisClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient(
          statusCode: 200,
          risposta: _rispostaOpenAi(_campiCompleti),
        ),
      );

      final risultato = await client.estraiCopertina(Uint8List(0));

      expect(risultato.title, 'Amazing Spider-Man');
      expect(risultato.issueNumberLabel, '300');
      expect(risultato.publisher, 'Marvel');
      expect(risultato.seriesName, 'The Amazing Spider-Man');
      expect(risultato.isbn, isNull);
      expect(risultato.barcode, '076194130132500111');
      expect(risultato.price, '€ 1,50');
      expect(risultato.raw['authors'], ['David Michelinie']);
      expect(risultato.characters, ['Spider-Man', 'Venom']);
      expect(risultato.coverStyleTags, ['stile realistico']);
      expect(risultato.visualElementTags, ['sfondo con esplosione']);
      expect(risultato.recognizedPublisherLogo, 'Marvel');
      expect(risultato.recognizedSeriesLogo, isNull);
      expect(risultato.printingType, 'Direct Edition');
      expect(risultato.classificazione, 'Rated T+');
      expect(
        risultato.description,
        'Peter Parker affronta Venom in un confronto decisivo.',
      );
    },
  );

  test("un campo non trovato resta null, non genera un'eccezione", () async {
    final campi = Map<String, dynamic>.from(_campiCompleti)
      ..['title'] = null
      ..['publisher'] = null
      ..['printingType'] = null
      ..['classificazione'] = null
      ..['description'] = null;
    final client = OpenAiCoverAnalysisClient(
      settingsRepository: await _settingsConApiKey(),
      httpClient: _FakeHttpClient(
        statusCode: 200,
        risposta: _rispostaOpenAi(campi),
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
    'un rifiuto del modello (blocco refusal) solleva CoverAnalysisException con il motivo',
    () async {
      final client = OpenAiCoverAnalysisClient(
        settingsRepository: await _settingsConApiKey(),
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
    final client = OpenAiCoverAnalysisClient(
      settingsRepository: await _settingsConApiKey(),
      httpClient: _FakeHttpClient(statusCode: 500, risposta: 'errore interno'),
    );

    await expectLater(
      () => client.estraiCopertina(Uint8List(0)),
      throwsA(isA<CoverAnalysisException>()),
    );
  });

  test(
    'una risposta senza messaggio in output solleva CoverAnalysisException',
    () async {
      final client = OpenAiCoverAnalysisClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient(
          statusCode: 200,
          risposta: jsonEncode({'output': <dynamic>[]}),
        ),
      );

      await expectLater(
        () => client.estraiCopertina(Uint8List(0)),
        throwsA(isA<CoverAnalysisException>()),
      );
    },
  );

  test(
    'senza API key configurata nelle Impostazioni solleva CoverAnalysisException senza chiamare la rete',
    () async {
      final fake = _FakeHttpClient(
        statusCode: 200,
        risposta: _rispostaOpenAi(_campiCompleti),
      );
      final client = OpenAiCoverAnalysisClient(
        settingsRepository: SettingsRepository.inMemoria(),
        httpClient: fake,
      );

      await expectLater(
        () => client.estraiCopertina(Uint8List(0)),
        throwsA(isA<CoverAnalysisException>()),
      );
      expect(fake.ultimaRichiesta, isNull);
    },
  );
}
