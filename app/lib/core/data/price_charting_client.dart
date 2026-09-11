import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/errore_configurazione.dart';

const _apiUrl = 'https://www.pricecharting.com/api/product';

/// API pubblica gratuita, senza chiave, della Banca Centrale Europea
/// (Frankfurter, https://www.frankfurter.dev) per il tasso di cambio
/// USD→EUR — non menzionata da ADR-0006 (che fissa solo il *provider di
/// pricing*, PriceCharting): nessun'altra scelta di conversione valuta
/// esiste nel codebase, e introdurne una richiede solo questa singola
/// chiamata, non una nuova configurazione in Impostazioni (a differenza del
/// provider di pricing, qui non serve né API key né un ruolo dedicato in
/// §12). Un fallimento di questa chiamata è trattato come lo stesso "errore
/// transitorio" (§35.4) di un fallimento PriceCharting: dal punto di vista
/// dell'utente l'intero calcolo del Valore stimato non è riuscito, la
/// distinzione fra le due cause non aggiungerebbe nulla di attuabile.
const _exchangeRateUrl = 'https://api.frankfurter.dev/v1/latest';

/// Timeout di ciascuna chiamata HTTP (PriceCharting o tasso di cambio) —
/// stesso valore di `coverAnalysisTimeout`/`comicVineTimeout`, stesso
/// motivo: senza un timeout esplicito una richiesta senza risposta
/// lascerebbe il Valore stimato bloccato in `inCorso` a tempo indeterminato
/// invece di finire `fallita` (§35.4).
const priceChartingTimeout = Duration(seconds: 45);

/// Intervallo minimo fra due chiamate consecutive all'API PriceCharting
/// (ADR-0006: rate-limit di 1 chiamata/secondo; superarlo ripetutamente
/// porta al blocco dell'account) — margine di sicurezza sopra il minimo
/// esatto di 1000ms, per assorbire l'imprecisione di `DateTime.now()` e
/// della latenza locale. Rilevante perché coerente con un innesco solo
/// event-driven (§35.3): senza throttling, un utente che modifica la
/// Condizione di due Copie in rapida successione potrebbe superare il
/// limite.
const _intervalloMinimoChiamateDefault = Duration(milliseconds: 1100);

/// Mapping Condizione→campo prezzo della risposta PriceCharting (§35.2,
/// fasce di grado decise su
/// [Mappatura Condizione↔scala di grading esterna e copertura variant/edizioni non coperte](https://github.com/saviogiordano/MyComicBrain/issues/160)):
/// quel ticket ha fissato solo le *fasce* per nome (tabella in
/// `docs/requisiti.md` §35.2); la scelta del campo esatto della risposta
/// PriceCharting per ciascuna fascia è di competenza di questo ticket,
/// costruita dalla sezione "Prices API: Description of Keys" della
/// documentazione ufficiale (riportata in
/// `docs/research/valutazione-fumetti-api-pricing.md` §1, branch
/// `research/valutazione-fumetti-api-pricing`) — non da una risposta reale
/// osservata, stessa cautela già espressa in ADR-0006, da riverificare con
/// una chiamata live. Per ogni fascia si sceglie il campo il cui grado noto
/// è più vicino al centro della fascia (es. Very Fine 7.5–9.0 → `graded-
/// price`, grado 8.0-8.5, centro 8.25). Fair (1.0–1.5) e Poor (0.5) non
/// hanno un campo dedicato sotto il grado 2.0 (Good) nella documentazione
/// ufficiale: ripiegano entrambi su `loose-price` (il prezzo "Ungraded",
/// nessun grado CGC associato) — il campo più basso disponibile, non un
/// prezzo preciso per quelle fasce specifiche.
const Map<CondizioneCopia, String> _campoPrezzoPerCondizione = {
  CondizioneCopia.mint: 'bgs-10-price',
  CondizioneCopia.nearMint: 'condition-10-price',
  CondizioneCopia.veryFine: 'graded-price',
  CondizioneCopia.fine: 'new-price',
  CondizioneCopia.veryGood: 'cib-price',
  CondizioneCopia.good: 'condition-9-price',
  CondizioneCopia.fair: 'loose-price',
  CondizioneCopia.poor: 'loose-price',
};

/// Una chiamata a PriceCharting (o al servizio di cambio valuta) fallita o
/// con risposta inattesa (rete, HTTP non-2xx, JSON inatteso) — trattata
/// come "errore transitorio" da §35.4, distinta dal `null` che
/// [PriceChartingClient.stimaValoreEur] ritorna quando l'Edizione/variant
/// semplicemente non è coperta dalla fonte (§35.2, "non disponibile": non
/// un fallimento).
class PriceChartingException implements Exception {
  PriceChartingException(this.message);

  final String message;

  @override
  String toString() => 'PriceChartingException: $message';
}

/// Interfaccia del client PriceCharting (ADR-0006), il provider di
/// valutazione (§35.1) che calcola il Valore stimato di una Copia (§35) —
/// stesso pattern architetturale di `CoverAnalysisClient`/`ComicVineClient`:
/// interfaccia dedicata per poter iniettare un fake nei test, un solo
/// provider implementato oggi (§35.1: "oggi solo PriceCharting").
abstract interface class PriceChartingClient {
  /// Interroga PriceCharting per titolo+numero(+editore) dell'Edizione
  /// (`title`/`seriesName`/`issueNumberLabel`/`publisher`, stessi campi
  /// letti da `ComicsRepository.copiaConEdizionePerId`), modulato dal grado
  /// CGC/Overstreet corrispondente a [condition] (§35.2 — `null` assume
  /// Very Fine come riferimento, stesso default della UI). Ritorna il
  /// prezzo già convertito in EUR (§35: "sempre convertito e mostrato in
  /// EUR indipendentemente dalla valuta nativa della fonte"), o `null` se
  /// l'Edizione/variant non è coperta dalla fonte (§35.2/§35.4: "non
  /// disponibile" — un esito legittimo, non un errore, quindi nessuna
  /// eccezione). Solleva [PriceChartingException] per un errore di
  /// rete/timeout/HTTP o quota/rate-limit superata (§35.4: "errore
  /// transitorio") — incluso il prefisso [prefissoConfigurazioneMancante]
  /// se il provider non è configurato nelle Impostazioni (§35.1), stesso
  /// pattern di `ComicVineClient`/`CoverAnalysisClient`, per quando il
  /// chiamante interroga il client senza controllare prima
  /// `SettingsRepository.apiKeyValutazione` (il modo — alternativo a questa
  /// eccezione — per il chiamante di sapere in anticipo se il provider è
  /// configurato, senza nemmeno interrogare il client, §35.1).
  Future<double?> stimaValoreEur({
    required String title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
    required CondizioneCopia? condition,
  });

  /// Verifica reale della configurazione corrente — stesso ruolo di
  /// `verificaConnessione` su `ComicVineClient`/`CoverAnalysisClient`, usata
  /// dal bottone "Verifica configurazione" della futura sezione
  /// Impostazioni "Provider valutazione" (§35.1, UI fuori scope da questo
  /// ticket). Ritorna normalmente se la configurazione è valida, altrimenti
  /// solleva [PriceChartingException].
  Future<void> verificaConnessione();
}

/// Chiama l'API REST `GET /api/product` di PriceCharting (nessun SDK Dart
/// ufficiale, stesso motivo di `ClaudeCoverAnalysisClient`/
/// `ComicVineHttpClient`). API key letta a runtime da [SettingsRepository]
/// (ruolo "Provider valutazione", §35.1) — non a build-time, stesso pattern
/// degli altri client.
class PriceChartingHttpClient implements PriceChartingClient {
  PriceChartingHttpClient({
    SettingsRepository? settingsRepository,
    http.Client? httpClient,
    Duration intervalloMinimoChiamate = _intervalloMinimoChiamateDefault,
  }) : _settingsRepository = settingsRepository,
       _httpClient = httpClient ?? http.Client(),
       _intervalloMinimoChiamate = intervalloMinimoChiamate;

  final SettingsRepository? _settingsRepository;
  final http.Client _httpClient;

  /// Di norma [_intervalloMinimoChiamate] (default costante) — iniettabile
  /// solo per i test, che altrimenti pagherebbero per intero il throttling
  /// reale ad ogni chiamata simulata.
  final Duration _intervalloMinimoChiamate;

  /// Timestamp dell'ultima chiamata a PriceCharting, per [_rispettaRateLimit]
  /// — stato di istanza: il provider Riverpod (`priceChartingClientProvider`
  /// in `providers.dart`) crea un'unica istanza per l'intera app, quindi
  /// resta valido throttlare per-istanza invece che con uno stato globale.
  DateTime? _ultimaChiamataPriceCharting;

  /// Legge l'API key da [SettingsRepository], sollevando
  /// [PriceChartingException] col prefisso [prefissoConfigurazioneMancante]
  /// (§12, stesso pattern di `ComicVineHttpClient._apiKeyRichiesta`) se
  /// manca — condivisa fra [stimaValoreEur] e [verificaConnessione].
  Future<String> _apiKeyRichiesta() async {
    final apiKey = await _settingsRepository?.apiKeyValutazione;
    if (apiKey == null || apiKey.isEmpty) {
      throw PriceChartingException(
        '${prefissoConfigurazioneMancante}Nessuna API key PriceCharting configurata nelle Impostazioni.',
      );
    }
    return apiKey;
  }

  /// Ricerca minima (`q=test`) per verificare che l'API key sia valida
  /// (stesso principio di `ComicVineHttpClient.verificaConnessione`):
  /// `_prodotto` solleva già [PriceChartingException] su una risposta HTTP
  /// non-2xx, incluso il caso di token non valido.
  @override
  Future<void> verificaConnessione() async {
    final apiKey = await _apiKeyRichiesta();
    await _prodotto(apiKey: apiKey, query: 'test');
  }

  @override
  Future<double?> stimaValoreEur({
    required String title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
    required CondizioneCopia? condition,
  }) async {
    final apiKey = await _apiKeyRichiesta();
    final query = _buildQuery(
      title: title,
      seriesName: seriesName,
      issueNumberLabel: issueNumberLabel,
      publisher: publisher,
    );

    final prodotto = await _prodotto(apiKey: apiKey, query: query);
    // Nessun prodotto trovato per la query (§35.2: Edizione/variant non
    // coperta dalla fonte) — "non disponibile", non un'eccezione.
    if (prodotto == null) return null;

    final campo =
        _campoPrezzoPerCondizione[condition ?? CondizioneCopia.veryFine]!;
    final centesimi = prodotto[campo] as int?;
    // Il prodotto esiste ma non ha un prezzo per questo grado specifico
    // (es. mai venduto graduato a quel livello) — stesso esito "non
    // disponibile" di un prodotto non trovato: nessun fallback a un grado
    // diverso, mostrerebbe un prezzo non pertinente come se fosse accurato
    // (stesso principio già fissato per Edizioni/variant su #160).
    if (centesimi == null) return null;

    return _convertiInEur(centesimi / 100);
  }

  /// `GET /api/product?t=<key>&q=<query>` — ricerca testuale libera
  /// (nessun parametro `publisher` dedicato documentato, vedi ricerca #158
  /// §1). Ritorna `null` se PriceCharting non trova alcun prodotto per
  /// [query] (`status: "error"` con una risposta HTTP comunque 200 —
  /// assunzione da "Description of Keys", da riverificare con una chiamata
  /// live: un vero fallimento di autenticazione/quota è invece atteso su
  /// uno status HTTP non-2xx, gestito sotto come [PriceChartingException]).
  Future<Map<String, dynamic>?> _prodotto({
    required String apiKey,
    required String query,
  }) async {
    await _rispettaRateLimit();

    final uri = Uri.parse(
      _apiUrl,
    ).replace(queryParameters: {'t': apiKey, 'q': query});

    final http.Response response;
    try {
      response = await _httpClient.get(uri).timeout(priceChartingTimeout);
    } on Object catch (e) {
      throw PriceChartingException(
        "Chiamata all'API PriceCharting fallita: $e",
      );
    }

    // La risposta è sempre JSON/UTF-8: `response.body` indovina la codifica
    // dal charset del content-type e cade su Latin-1 corrompendo i
    // caratteri non ASCII (stesso motivo di `ClaudeCoverAnalysisClient`/
    // `ComicVineHttpClient`).
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      throw PriceChartingException(
        'PriceCharting API ${response.statusCode}: $responseBody',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(responseBody) as Map<String, dynamic>;
    } on Object catch (e) {
      throw PriceChartingException('Risposta PriceCharting inattesa: $e');
    }

    if (body['status'] == 'error') return null;
    return body;
  }

  /// Applica il rate-limit di 1 chiamata/secondo (ADR-0006) attendendo, se
  /// necessario, prima di ogni chiamata effettiva a PriceCharting.
  Future<void> _rispettaRateLimit() async {
    final ultima = _ultimaChiamataPriceCharting;
    if (ultima != null) {
      final trascorso = DateTime.now().difference(ultima);
      if (trascorso < _intervalloMinimoChiamate) {
        await Future<void>.delayed(_intervalloMinimoChiamate - trascorso);
      }
    }
    _ultimaChiamataPriceCharting = DateTime.now();
  }

  /// Converte [valueUsd] in EUR tramite il tasso di cambio corrente
  /// (Frankfurter, vedi [_exchangeRateUrl]) — nessun rate-limit da
  /// rispettare, servizio distinto da PriceCharting.
  Future<double> _convertiInEur(double valueUsd) async {
    final uri = Uri.parse(
      _exchangeRateUrl,
    ).replace(queryParameters: {'base': 'USD', 'symbols': 'EUR'});

    final http.Response response;
    try {
      response = await _httpClient.get(uri).timeout(priceChartingTimeout);
    } on Object catch (e) {
      throw PriceChartingException('Conversione USD→EUR fallita: $e');
    }

    final responseBody = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw PriceChartingException(
        'Servizio di cambio valuta ${response.statusCode}: $responseBody',
      );
    }

    final num tasso;
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final rates = body['rates'] as Map<String, dynamic>;
      tasso = rates['EUR'] as num;
    } on Object catch (e) {
      throw PriceChartingException(
        'Risposta del servizio di cambio valuta inattesa: $e',
      );
    }

    return valueUsd * tasso;
  }
}

String _buildQuery({
  required String? title,
  required String? seriesName,
  required String? issueNumberLabel,
  required String? publisher,
}) {
  return [seriesName ?? title, issueNumberLabel, publisher]
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join(' ');
}
