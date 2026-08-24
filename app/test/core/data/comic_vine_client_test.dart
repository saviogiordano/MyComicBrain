import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/comic_vine_client.dart';

/// `http.Client` finto: risponde in base al `resources`/percorso della
/// richiesta (`volume` per la ricerca volumi, `/issues/` per il filtro per
/// numero, `issue` per la vecchia ricerca testuale libera), registrando
/// tutte le richieste inviate — a differenza di un fake a risposta fissa,
/// serve a testare il flusso a due passaggi (#60).
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({
    this.risultatiVolumi = const [],
    this.risultatiPerVolume = const {},
    this.risultatiTestoLibero = const [],
    this.statusCode = 1,
  });

  final List<Map<String, dynamic>> risultatiVolumi;

  /// Risultati del filtro `/issues/?filter=volume:<id>,...`, per id volume.
  final Map<int, List<Map<String, dynamic>>> risultatiPerVolume;
  final List<Map<String, dynamic>> risultatiTestoLibero;
  final int statusCode;

  final List<http.BaseRequest> richieste = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    richieste.add(request);
    final uri = request.url;

    final List<Map<String, dynamic>> risultati;
    if (uri.path.contains('/issues/')) {
      final filtro = uri.queryParameters['filter'] ?? '';
      final match = RegExp(r'volume:(\d+)').firstMatch(filtro);
      final volumeId = match == null ? null : int.parse(match.group(1)!);
      risultati = risultatiPerVolume[volumeId] ?? const [];
    } else if (uri.queryParameters['resources'] == 'volume') {
      risultati = risultatiVolumi;
    } else {
      risultati = risultatiTestoLibero;
    }

    return http.StreamedResponse(
      Stream.value(
        utf8.encode(_rispostaComicVine(risultati, statusCode: statusCode)),
      ),
      200,
    );
  }
}

String _rispostaComicVine(
  List<Map<String, dynamic>> results, {
  int statusCode = 1,
}) => jsonEncode({
  'error': statusCode == 1 ? 'OK' : "l'API key non è valida",
  'limit': 100,
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
  'volume': {
    'id': 222,
    'name': 'Amazing Fantasy',
    'site_detail_url': 'https://comicvine.gamespot.com/volume/',
  },
  'image': {
    'medium_url': 'https://comicvine.gamespot.com/a/uploads/medium.jpg',
  },
  'site_detail_url':
      'https://comicvine.gamespot.com/amazing-fantasy-15/4000-111000/',
};

Map<String, dynamic> _volume({
  required int id,
  required String name,
  String? publisher,
  int? countOfIssues,
}) => {
  'id': id,
  'name': name,
  if (publisher != null) 'publisher': {'name': publisher},
  'count_of_issues': ?countOfIssues,
};

void main() {
  group('con numero e serie/titolo disponibili (ricerca per volume, #60)', () {
    test(
      'cerca prima i volumi e poi filtra per numero nel volume scelto',
      () async {
        final fake = _FakeHttpClient(
          risultatiVolumi: [
            _volume(
              id: 2133,
              name: 'The X-Men',
              publisher: 'Marvel',
              countOfIssues: 141,
            ),
          ],
          risultatiPerVolume: {
            2133: [
              {
                'id': 20546,
                'name': 'Dark Phoenix',
                'issue_number': '135',
                'volume': {'id': 2133, 'name': 'The X-Men'},
                'image': {
                  'medium_url': 'https://comicvine.gamespot.com/x-men-135.jpg',
                },
                'site_detail_url':
                    'https://comicvine.gamespot.com/the-x-men-135-dark-phoenix/4000-20546/',
              },
            ],
          },
        );
        final client = ComicVineHttpClient(httpClient: fake);

        final risultati = await client.cercaIssue(
          title: null,
          seriesName: 'Uncanny X-Men',
          issueNumberLabel: '135',
          publisher: 'Marvel Comics Group',
        );

        expect(risultati, hasLength(1));
        expect(risultati.single.issueNumber, '135');
        expect(risultati.single.volumeName, 'The X-Men');

        expect(fake.richieste, hasLength(2));
        final ricercaVolumi = fake.richieste[0].url;
        expect(ricercaVolumi.queryParameters['resources'], 'volume');
        expect(ricercaVolumi.queryParameters['query'], 'Uncanny X-Men');
        final filtroIssue = fake.richieste[1].url;
        expect(filtroIssue.path, contains('/issues/'));
        expect(
          filtroIssue.queryParameters['filter'],
          'volume:2133,issue_number:135',
        );
      },
    );

    test(
      'ripulisce il prefisso "#" dall\'etichetta di numero prima del filtro e del parsing intero',
      () async {
        // issue_number su ComicVine non porta mai il "#": un'etichetta letta
        // da copertina come "#700" (la convenzione più comune) non deve
        // rompere né il filtro esatto né il parsing intero per
        // count_of_issues, altrimenti la ricerca per volume introdotta su
        // #60 fallisce in silenzio per praticamente ogni albo USA.
        final fake = _FakeHttpClient(
          risultatiVolumi: [
            _volume(
              id: 78701,
              name: 'The Amazing Spider-Man',
              publisher: 'Marvel',
              countOfIssues: 58,
            ),
            _volume(
              id: 2127,
              name: 'The Amazing Spider-Man',
              publisher: 'Marvel',
              countOfIssues: 651,
            ),
          ],
          risultatiPerVolume: {
            2127: [
              {
                'id': 373805,
                'name': 'Dying Wish',
                'issue_number': '700',
                'volume': {'id': 2127, 'name': 'The Amazing Spider-Man'},
                'image': null,
                'site_detail_url':
                    'https://comicvine.gamespot.com/the-amazing-spider-man-700/4000-373805/',
              },
            ],
          },
        );
        final client = ComicVineHttpClient(httpClient: fake);

        final risultati = await client.cercaIssue(
          title: null,
          seriesName: 'The Amazing Spider-Man',
          issueNumberLabel: '#700',
          publisher: 'Marvel',
        );

        expect(risultati, hasLength(1));
        expect(risultati.single.issueNumber, '700');
        // 2127 (651 albi, sotto il 700 cercato per una numerazione "legacy"
        // con salti — caso reale verificato dal vivo) va comunque
        // interrogato con "700" pulito, non "#700": la sola prova che
        // conta è che il filtro usi il numero senza "#".
        final filtroPer2127 = fake.richieste.where(
          (r) =>
              r.url.path.contains('/issues/') &&
              r.url.queryParameters['filter'] == 'volume:2127,issue_number:700',
        );
        expect(filtroPer2127, hasLength(1));
      },
    );

    test(
      'predilige un volume con abbastanza albi quando più volumi combaciano per nome',
      () async {
        // Scenario reale: molte ripartenze recenti si chiamano esattamente
        // come la testata originale e pareggiano per somiglianza testuale —
        // solo l'idoneità per numero (count_of_issues) le distingue. Più di
        // 5 volumi per esercitare anche il tetto [_massimoVolumiCandidati].
        final fake = _FakeHttpClient(
          risultatiVolumi: [
            _volume(
              id: 2133,
              name: 'The X-Men',
              publisher: 'Marvel',
              countOfIssues: 141,
            ),
            for (final ripartenza in [
              (id: 43785, count: 20),
              (id: 57181, count: 36),
              (id: 87825, count: 2),
              (id: 115285, count: 22),
              (id: 159189, count: 34),
              (id: 87190, count: 19),
            ])
              _volume(
                id: ripartenza.id,
                name: 'Uncanny X-Men',
                publisher: 'Marvel',
                countOfIssues: ripartenza.count,
              ),
          ],
          risultatiPerVolume: {
            2133: [
              {
                'id': 20546,
                'name': 'Dark Phoenix',
                'issue_number': '135',
                'volume': {'id': 2133, 'name': 'The X-Men'},
                'image': null,
                'site_detail_url':
                    'https://comicvine.gamespot.com/the-x-men-135-dark-phoenix/4000-20546/',
              },
            ],
          },
        );
        final client = ComicVineHttpClient(httpClient: fake);

        final risultati = await client.cercaIssue(
          title: null,
          seriesName: 'Uncanny X-Men',
          issueNumberLabel: '135',
          publisher: 'Marvel',
        );

        expect(risultati, hasLength(1));
        expect(risultati.single.volumeName, 'The X-Men');
        final chiamateFiltro = fake.richieste.where(
          (r) => r.url.path.contains('/issues/'),
        );
        // Il tetto sui volumi candidati resta rispettato anche con 7 volumi
        // trovati dalla ricerca.
        expect(chiamateFiltro.length, lessThanOrEqualTo(5));
        expect(
          chiamateFiltro,
          contains(
            predicate<http.BaseRequest>(
              (r) =>
                  r.url.queryParameters['filter'] ==
                  'volume:2133,issue_number:135',
            ),
          ),
        );
      },
    );

    test(
      'ripiega sulla ricerca testuale libera se nessun volume candidato contiene quel numero',
      () async {
        final fake = _FakeHttpClient(
          risultatiVolumi: [
            _volume(id: 2133, name: 'The X-Men', countOfIssues: 141),
          ],
          risultatiTestoLibero: [_issueCompleta],
        );
        final client = ComicVineHttpClient(httpClient: fake);

        final risultati = await client.cercaIssue(
          title: null,
          seriesName: 'The X-Men',
          issueNumberLabel: '999',
          publisher: null,
        );

        expect(risultati, hasLength(1));
        expect(risultati.single.name, 'Amazing Fantasy');
        final ultima = fake.richieste.last.url;
        expect(ultima.queryParameters['resources'], 'issue');
      },
    );

    test('non scarta un volume con count_of_issues mancante', () async {
      final fake = _FakeHttpClient(
        risultatiVolumi: [_volume(id: 2133, name: 'The X-Men')],
        risultatiPerVolume: {
          2133: [
            {
              'id': 20546,
              'name': 'Dark Phoenix',
              'issue_number': '135',
              'volume': {'id': 2133, 'name': 'The X-Men'},
              'image': null,
              'site_detail_url':
                  'https://comicvine.gamespot.com/the-x-men-135-dark-phoenix/4000-20546/',
            },
          ],
        },
      );
      final client = ComicVineHttpClient(httpClient: fake);

      final risultati = await client.cercaIssue(
        title: null,
        seriesName: 'The X-Men',
        issueNumberLabel: '135',
        publisher: null,
      );

      expect(risultati, hasLength(1));
    });
  });

  group('fallback su ricerca testuale libera (comportamento precedente)', () {
    test(
      'usa la ricerca testuale libera quando issueNumberLabel è null',
      () async {
        final fake = _FakeHttpClient(risultatiTestoLibero: [_issueCompleta]);
        final client = ComicVineHttpClient(httpClient: fake);

        final risultati = await client.cercaIssue(
          title: 'Amazing Fantasy',
          seriesName: 'Amazing Fantasy',
          issueNumberLabel: null,
          publisher: 'Marvel',
        );

        expect(risultati, hasLength(1));
        expect(fake.richieste, hasLength(1));
        final uri = fake.richieste.single.url;
        expect(uri.queryParameters['query'], 'Amazing Fantasy Amazing Fantasy');
        expect(uri.queryParameters['resources'], 'issue');
        expect(
          uri.queryParameters['field_list'],
          'id,name,issue_number,volume,image,site_detail_url',
        );
      },
    );

    test(
      'usa issueNumberLabel+publisher come fallback quando title e seriesName sono null',
      () async {
        final fake = _FakeHttpClient();
        final client = ComicVineHttpClient(httpClient: fake);

        await client.cercaIssue(
          title: null,
          seriesName: null,
          issueNumberLabel: '15',
          publisher: 'Marvel',
        );

        expect(fake.richieste, hasLength(1));
        final uri = fake.richieste.single.url;
        expect(uri.queryParameters['query'], '15 Marvel');
        expect(uri.queryParameters['resources'], 'issue');
      },
    );

    test("non chiama l'API se tutti i campi OCR sono null", () async {
      final fake = _FakeHttpClient();
      final client = ComicVineHttpClient(httpClient: fake);

      final risultati = await client.cercaIssue(
        title: null,
        seriesName: null,
        issueNumberLabel: null,
        publisher: null,
      );

      expect(risultati, isEmpty);
      expect(fake.richieste, isEmpty);
    });

    test(
      "un campo volume o image mancante nel risultato non genera un'eccezione",
      () async {
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
            risultatiTestoLibero: [issueSenzaVolumeEImage],
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
      },
    );
  });

  group('errori', () {
    test(
      'un status_code diverso da 1 solleva ComicVineException con il messaggio di errore',
      () async {
        final client = ComicVineHttpClient(
          httpClient: _FakeHttpClient(statusCode: 100),
        );

        await expectLater(
          () => client.cercaIssue(
            title: 'x',
            seriesName: null,
            issueNumberLabel: null,
            publisher: null,
          ),
          throwsA(
            isA<ComicVineException>().having(
              (e) => e.message,
              'message',
              contains("l'API key non è valida"),
            ),
          ),
        );
      },
    );

    test('una risposta HTTP non-2xx solleva ComicVineException', () async {
      final client = ComicVineHttpClient(httpClient: _FakeHttpClientNon2xx());

      await expectLater(
        () => client.cercaIssue(
          title: 'x',
          seriesName: null,
          issueNumberLabel: null,
          publisher: null,
        ),
        throwsA(isA<ComicVineException>()),
      );
    });

    test('una risposta non JSON valido solleva ComicVineException', () async {
      final client = ComicVineHttpClient(
        httpClient: _FakeHttpClientRispostaInvalida(),
      );

      await expectLater(
        () => client.cercaIssue(
          title: 'x',
          seriesName: null,
          issueNumberLabel: null,
          publisher: null,
        ),
        throwsA(isA<ComicVineException>()),
      );
    });
  });
}

class _FakeHttpClientNon2xx extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode('errore interno')),
      500,
    );
  }
}

class _FakeHttpClientRispostaInvalida extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream.value(utf8.encode('non è json')), 200);
  }
}
