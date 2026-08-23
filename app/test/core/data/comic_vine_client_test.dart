import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/comic_vine_client.dart';

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

String _rispostaComicVine(List<Map<String, dynamic>> results, {int statusCode = 1}) => jsonEncode({
  'error': statusCode == 1 ? 'OK' : "l'API key non è valida",
  'limit': 10,
  'offset': 0,
  'number_of_page_results': results.length,
  'number_of_total_results': results.length,
  'status_code': statusCode,
  'results': results,
});

const Map<String, dynamic> _issueCompleta = {
  'id': 111000,
  'name': 'Amazing Fantasy',
  'issue_number': '15',
  'volume': {'id': 222, 'name': 'Amazing Fantasy', 'site_detail_url': 'https://comicvine.gamespot.com/volume/'},
  'image': {'medium_url': 'https://comicvine.gamespot.com/a/uploads/medium.jpg'},
  'site_detail_url': 'https://comicvine.gamespot.com/amazing-fantasy-15/4000-111000/',
};

void main() {
  test('estrae i campi rilevanti per lo scoring da una risposta 200 con status_code 1', () async {
    final client = ComicVineHttpClient(
      httpClient: _FakeHttpClient(statusCode: 200, risposta: _rispostaComicVine([_issueCompleta])),
    );

    final risultati = await client.cercaIssue(
      title: 'Amazing Fantasy',
      seriesName: 'Amazing Fantasy',
      issueNumberLabel: '15',
      publisher: 'Marvel',
    );

    expect(risultati, hasLength(1));
    final match = risultati.single;
    expect(match.id, 111000);
    expect(match.name, 'Amazing Fantasy');
    expect(match.issueNumber, '15');
    expect(match.volumeName, 'Amazing Fantasy');
    expect(match.coverImageUrl, 'https://comicvine.gamespot.com/a/uploads/medium.jpg');
    expect(match.siteDetailUrl, 'https://comicvine.gamespot.com/amazing-fantasy-15/4000-111000/');
  });

  test('costruisce la query da seriesName+title quando entrambi presenti', () async {
    final fake = _FakeHttpClient(statusCode: 200, risposta: _rispostaComicVine([]));
    final client = ComicVineHttpClient(httpClient: fake);

    await client.cercaIssue(
      title: 'Amazing Fantasy',
      seriesName: 'Amazing Fantasy',
      issueNumberLabel: '15',
      publisher: 'Marvel',
    );

    final uri = (fake.ultimaRichiesta! as http.Request).url;
    expect(uri.queryParameters['query'], 'Amazing Fantasy Amazing Fantasy');
    expect(uri.queryParameters['resources'], 'issue');
    expect(uri.queryParameters['field_list'], 'id,name,issue_number,volume,image,site_detail_url');
  });

  test('usa issueNumberLabel+publisher come fallback quando title e seriesName sono null', () async {
    final fake = _FakeHttpClient(statusCode: 200, risposta: _rispostaComicVine([]));
    final client = ComicVineHttpClient(httpClient: fake);

    await client.cercaIssue(title: null, seriesName: null, issueNumberLabel: '15', publisher: 'Marvel');

    final uri = (fake.ultimaRichiesta! as http.Request).url;
    expect(uri.queryParameters['query'], '15 Marvel');
  });

  test("non chiama l'API se tutti i campi OCR sono null", () async {
    final fake = _FakeHttpClient(statusCode: 200, risposta: _rispostaComicVine([]));
    final client = ComicVineHttpClient(httpClient: fake);

    final risultati = await client.cercaIssue(
      title: null,
      seriesName: null,
      issueNumberLabel: null,
      publisher: null,
    );

    expect(risultati, isEmpty);
    expect(fake.ultimaRichiesta, isNull);
  });

  test("un campo volume o image mancante nel risultato non genera un'eccezione", () async {
    final issueSenzaVolumeEImage = {
      'id': 999,
      'name': null,
      'issue_number': '1',
      'volume': null,
      'image': null,
      'site_detail_url': 'https://comicvine.gamespot.com/x/1-999/',
    };
    final client = ComicVineHttpClient(
      httpClient: _FakeHttpClient(
        statusCode: 200,
        risposta: _rispostaComicVine([issueSenzaVolumeEImage]),
      ),
    );

    final risultati = await client.cercaIssue(
      title: null,
      seriesName: null,
      issueNumberLabel: '1',
      publisher: null,
    );

    final match = risultati.single;
    expect(match.name, isNull);
    expect(match.volumeName, isNull);
    expect(match.coverImageUrl, isNull);
  });

  test('un status_code diverso da 1 solleva ComicVineException con il messaggio di errore', () async {
    final client = ComicVineHttpClient(
      httpClient: _FakeHttpClient(
        statusCode: 200,
        risposta: _rispostaComicVine([], statusCode: 100),
      ),
    );

    await expectLater(
      () => client.cercaIssue(title: 'x', seriesName: null, issueNumberLabel: null, publisher: null),
      throwsA(
        isA<ComicVineException>().having(
          (e) => e.message,
          'message',
          contains("l'API key non è valida"),
        ),
      ),
    );
  });

  test('una risposta HTTP non-2xx solleva ComicVineException', () async {
    final client = ComicVineHttpClient(
      httpClient: _FakeHttpClient(statusCode: 500, risposta: 'errore interno'),
    );

    await expectLater(
      () => client.cercaIssue(title: 'x', seriesName: null, issueNumberLabel: null, publisher: null),
      throwsA(isA<ComicVineException>()),
    );
  });

  test('una risposta non JSON valido solleva ComicVineException', () async {
    final client = ComicVineHttpClient(
      httpClient: _FakeHttpClient(statusCode: 200, risposta: 'non è json'),
    );

    await expectLater(
      () => client.cercaIssue(title: 'x', seriesName: null, issueNumberLabel: null, publisher: null),
      throwsA(isA<ComicVineException>()),
    );
  });
}
