import 'dart:convert';

import 'package:http/http.dart' as http;

/// API pubblica gratuita, senza chiave, della Banca Centrale Europea
/// (Frankfurter, https://www.frankfurter.dev) per il tasso di cambio
/// USD→EUR — nessuna configurazione richiesta, a differenza del provider di
/// valutazione PriceCharting (ADR-0006, oggi non integrato).
const _exchangeRateUrl = 'https://api.frankfurter.dev/v1/latest';

/// Tasso di ripiego usato solo se [ExchangeRateClient.tassoUsdEur] non
/// riesce a raggiungere il servizio (rete assente/timeout): un valore
/// approssimativo ma ragionevole è preferibile a bloccare il calcolo del
/// "Speso finora" (§4.1) — l'errore introdotto resta contenuto per un
/// totale aggregato di una collezione personale, non per una singola
/// transazione finanziaria.
const tassoUsdEurDiRipiego = 0.92;

const _timeout = Duration(seconds: 10);

/// Interroga il tasso di cambio corrente USD→EUR, usato per convertire nel
/// totale "Speso finora" (§4.1) le Copie il cui prezzo di acquisto è stato
/// letto in dollari da una Scansione (`Copie.purchasePriceCurrency`).
abstract interface class ExchangeRateClient {
  Future<double> tassoUsdEur();
}

class FrankfurterExchangeRateClient implements ExchangeRateClient {
  FrankfurterExchangeRateClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  Future<double> tassoUsdEur() async {
    final uri = Uri.parse(
      _exchangeRateUrl,
    ).replace(queryParameters: {'base': 'USD', 'symbols': 'EUR'});

    try {
      final response = await _httpClient.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return tassoUsdEurDiRipiego;

      final body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final rates = body['rates'] as Map<String, dynamic>;
      final tasso = rates['EUR'] as num?;
      return tasso?.toDouble() ?? tassoUsdEurDiRipiego;
    } on Object {
      return tassoUsdEurDiRipiego;
    }
  }
}
