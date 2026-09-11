import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/price_charting_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/errore_configurazione.dart';

/// `http.Client` finto: risponde in base all'host della richiesta
/// (`pricecharting.com` per il prodotto, `frankfurter.dev` per il tasso di
/// cambio), registrando tutte le richieste inviate.
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({
    this.prodotto = const {'status': 'success'},
    this.statusCodeProdotto = 200,
    this.tassoEur = 0.9,
    this.statusCodeCambio = 200,
  });

  final Map<String, dynamic> prodotto;
  final int statusCodeProdotto;
  final num tassoEur;
  final int statusCodeCambio;

  final List<http.BaseRequest> richieste = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    richieste.add(request);
    final uri = request.url;

    if (uri.host.contains('frankfurter')) {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'amount': 1.0,
              'base': 'USD',
              'rates': {'EUR': tassoEur},
            }),
          ),
        ),
        statusCodeCambio,
      );
    }

    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(prodotto))),
      statusCodeProdotto,
    );
  }
}

Future<SettingsRepository> _settingsConApiKey() async {
  final settings = SettingsRepository.inMemoria();
  await settings.impostaApiKeyValutazione('chiave-test');
  return settings;
}

void main() {
  test(
    'restituisce il prezzo del campo di Very Fine (default) convertito in EUR',
    () async {
      final fake = _FakeHttpClient(
        prodotto: {'status': 'success', 'graded-price': 1000},
      );
      final client = PriceChartingHttpClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: fake,
      );

      final valore = await client.stimaValoreEur(
        title: 'Amazing Spider-Man',
        seriesName: 'The Amazing Spider-Man',
        issueNumberLabel: '300',
        publisher: 'Marvel',
        condition: null,
      );

      // 1000 centesimi = 10.00 USD * 0.9 = 9.00 EUR.
      expect(valore, closeTo(9.0, 0.0001));
      final richiestaProdotto = fake.richieste.firstWhere(
        (r) => r.url.host.contains('pricecharting'),
      );
      expect(richiestaProdotto.url.queryParameters['t'], 'chiave-test');
      expect(
        richiestaProdotto.url.queryParameters['q'],
        'The Amazing Spider-Man 300 Marvel',
      );
    },
  );

  test('usa il campo corretto per ogni Condizione', () async {
    final fake = _FakeHttpClient(
      prodotto: {
        'status': 'success',
        'bgs-10-price': 100000,
        'condition-10-price': 50000,
        'graded-price': 10000,
        'new-price': 5000,
        'cib-price': 2000,
        'condition-9-price': 1000,
        'loose-price': 500,
      },
      tassoEur: 1,
    );
    final client = PriceChartingHttpClient(
      settingsRepository: await _settingsConApiKey(),
      httpClient: fake,
      // Niente rate-limit reale qui: il test fa 8 chiamate consecutive solo
      // per verificare il mapping campo↔Condizione, non il throttling
      // (coperto a parte sotto).
      intervalloMinimoChiamate: Duration.zero,
    );

    Future<double?> valorePer(CondizioneCopia? condizione) =>
        client.stimaValoreEur(
          title: 'Test',
          seriesName: null,
          issueNumberLabel: '1',
          publisher: null,
          condition: condizione,
        );

    expect(await valorePer(CondizioneCopia.mint), closeTo(1000, 0.0001));
    expect(await valorePer(CondizioneCopia.nearMint), closeTo(500, 0.0001));
    expect(await valorePer(CondizioneCopia.veryFine), closeTo(100, 0.0001));
    expect(await valorePer(CondizioneCopia.fine), closeTo(50, 0.0001));
    expect(await valorePer(CondizioneCopia.veryGood), closeTo(20, 0.0001));
    expect(await valorePer(CondizioneCopia.good), closeTo(10, 0.0001));
    expect(await valorePer(CondizioneCopia.fair), closeTo(5, 0.0001));
    expect(await valorePer(CondizioneCopia.poor), closeTo(5, 0.0001));
  });

  test(
    'rispetta il rate-limit di 1 chiamata/secondo attendendo fra due chiamate '
    'consecutive (ADR-0006)',
    () async {
      final fake = _FakeHttpClient(
        prodotto: {'status': 'success', 'graded-price': 100},
      );
      final client = PriceChartingHttpClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: fake,
        intervalloMinimoChiamate: const Duration(milliseconds: 200),
      );
      Future<double?> chiama() => client.stimaValoreEur(
        title: 'Test',
        seriesName: null,
        issueNumberLabel: '1',
        publisher: null,
        condition: null,
      );

      await chiama();
      final cronometro = Stopwatch()..start();
      await chiama();
      cronometro.stop();

      expect(cronometro.elapsedMilliseconds, greaterThanOrEqualTo(190));
    },
  );

  test(
    'nessun prodotto trovato (status "error") ritorna null, non solleva '
    "un'eccezione",
    () async {
      final fake = _FakeHttpClient(prodotto: {'status': 'error'});
      final client = PriceChartingHttpClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: fake,
      );

      final valore = await client.stimaValoreEur(
        title: 'Edizione italiana introvabile',
        seriesName: null,
        issueNumberLabel: '1',
        publisher: null,
        condition: null,
      );

      expect(valore, isNull);
    },
  );

  test(
    'prodotto trovato ma senza prezzo per il grado richiesto ritorna null',
    () async {
      final fake = _FakeHttpClient(
        prodotto: {'status': 'success', 'condition-9-price': 1000},
      );
      final client = PriceChartingHttpClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: fake,
      );

      final valore = await client.stimaValoreEur(
        title: 'Test',
        seriesName: null,
        issueNumberLabel: '1',
        publisher: null,
        condition: CondizioneCopia.mint,
      );

      expect(valore, isNull);
    },
  );

  test(
    'una risposta HTTP non-2xx da PriceCharting solleva PriceChartingException',
    () async {
      final fake = _FakeHttpClient(statusCodeProdotto: 500);
      final client = PriceChartingHttpClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: fake,
      );

      await expectLater(
        () => client.stimaValoreEur(
          title: 'Test',
          seriesName: null,
          issueNumberLabel: '1',
          publisher: null,
          condition: null,
        ),
        throwsA(isA<PriceChartingException>()),
      );
    },
  );

  test(
    'un fallimento del servizio di cambio valuta solleva PriceChartingException',
    () async {
      final fake = _FakeHttpClient(
        prodotto: {'status': 'success', 'graded-price': 1000},
        statusCodeCambio: 503,
      );
      final client = PriceChartingHttpClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: fake,
      );

      await expectLater(
        () => client.stimaValoreEur(
          title: 'Test',
          seriesName: null,
          issueNumberLabel: '1',
          publisher: null,
          condition: null,
        ),
        throwsA(isA<PriceChartingException>()),
      );
    },
  );

  test(
    'senza API key configurata nelle Impostazioni solleva PriceChartingException '
    'di configurazione mancante, senza chiamare la rete',
    () async {
      final fake = _FakeHttpClient();
      final client = PriceChartingHttpClient(
        settingsRepository: SettingsRepository.inMemoria(),
        httpClient: fake,
      );

      await expectLater(
        () => client.stimaValoreEur(
          title: 'Test',
          seriesName: null,
          issueNumberLabel: '1',
          publisher: null,
          condition: null,
        ),
        throwsA(
          isA<PriceChartingException>().having(
            (e) => erroreConfigurazioneMancante(e.toString()),
            'configurazione mancante',
            isTrue,
          ),
        ),
      );
      expect(fake.richieste, isEmpty);
    },
  );

  test(
    'senza SettingsRepository (client costruito senza DI) solleva PriceChartingException',
    () async {
      final client = PriceChartingHttpClient();

      await expectLater(
        () => client.stimaValoreEur(
          title: 'Test',
          seriesName: null,
          issueNumberLabel: '1',
          publisher: null,
          condition: null,
        ),
        throwsA(isA<PriceChartingException>()),
      );
    },
  );

  group('verificaConnessione', () {
    test('con risposta 200 non solleva nulla', () async {
      final client = PriceChartingHttpClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient(),
      );

      await client.verificaConnessione();
    });

    test('con risposta non-200 solleva PriceChartingException', () async {
      final client = PriceChartingHttpClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient(statusCodeProdotto: 401),
      );

      await expectLater(
        client.verificaConnessione,
        throwsA(isA<PriceChartingException>()),
      );
    });

    test(
      'senza API key configurata solleva un errore di configurazione mancante, '
      'senza chiamare la rete',
      () async {
        final fake = _FakeHttpClient();
        final client = PriceChartingHttpClient(
          settingsRepository: SettingsRepository.inMemoria(),
          httpClient: fake,
        );

        await expectLater(
          client.verificaConnessione,
          throwsA(isA<PriceChartingException>()),
        );
        expect(fake.richieste, isEmpty);
      },
    );
  });
}
