import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';

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
    return http.StreamedResponse(Stream.value(utf8.encode(risposta)), statusCode);
  }
}

String _rispostaClaude(Map<String, dynamic> campi) => jsonEncode({
  'content': [
    {'type': 'text', 'text': jsonEncode(campi)},
  ],
});

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
};

void main() {
  test('estrae i campi grezzi da una risposta 200 conforme allo schema', () async {
    final client = ClaudeCoverAnalysisClient(
      httpClient: _FakeHttpClient(statusCode: 200, risposta: _rispostaClaude(_campiCompleti)),
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
  });

  test("un campo non trovato da Claude resta null, non genera un'eccezione", () async {
    final campi = Map<String, dynamic>.from(_campiCompleti)
      ..['title'] = null
      ..['publisher'] = null;
    final client = ClaudeCoverAnalysisClient(
      httpClient: _FakeHttpClient(statusCode: 200, risposta: _rispostaClaude(campi)),
    );

    final risultato = await client.estraiCopertina(Uint8List(0));

    expect(risultato.title, isNull);
    expect(risultato.publisher, isNull);
  });

  test(
    'un elemento di computer vision non riconosciuto resta lista vuota/null, non genera '
    "un'eccezione",
    () async {
      final campi = Map<String, dynamic>.from(_campiCompleti)
        ..['characters'] = <String>[]
        ..['coverStyleTags'] = <String>[]
        ..['visualElementTags'] = <String>[]
        ..['recognizedPublisherLogo'] = null
        ..['recognizedSeriesLogo'] = null;
      final client = ClaudeCoverAnalysisClient(
        httpClient: _FakeHttpClient(statusCode: 200, risposta: _rispostaClaude(campi)),
      );

      final risultato = await client.estraiCopertina(Uint8List(0));

      expect(risultato.characters, isEmpty);
      expect(risultato.coverStyleTags, isEmpty);
      expect(risultato.visualElementTags, isEmpty);
      expect(risultato.recognizedPublisherLogo, isNull);
      expect(risultato.recognizedSeriesLogo, isNull);
    },
  );

  test('una risposta HTTP non-2xx solleva ClaudeCoverAnalysisException', () async {
    final client = ClaudeCoverAnalysisClient(
      httpClient: _FakeHttpClient(statusCode: 500, risposta: 'errore interno'),
    );

    await expectLater(
      () => client.estraiCopertina(Uint8List(0)),
      throwsA(isA<ClaudeCoverAnalysisException>()),
    );
  });

  test('una risposta senza contenuto testuale solleva ClaudeCoverAnalysisException', () async {
    final client = ClaudeCoverAnalysisClient(
      httpClient: _FakeHttpClient(statusCode: 200, risposta: jsonEncode({'content': <dynamic>[]})),
    );

    await expectLater(
      () => client.estraiCopertina(Uint8List(0)),
      throwsA(isA<ClaudeCoverAnalysisException>()),
    );
  });
}
