import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/comic_vine_api_config.dart';

const _searchUrl = 'https://comicvine.gamespot.com/api/search/';

/// Solo i campi che servono al parsing sotto — economizza la risposta,
/// coerente con la raccomandazione della documentazione ufficiale di fare
/// caching/uso parsimonioso dell'API (rate limit 200 richieste/risorsa/ora,
/// vedi `docs/research/comics-external-database.md` §1.2).
const _fieldList = 'id,name,issue_number,volume,image,site_detail_url';

/// Timeout della chiamata HTTP a ComicVine — stesso valore di
/// `coverAnalysisTimeout` (`cover_analysis_client.dart`): senza un timeout
/// esplicito una ricerca senza risposta lascerebbe l'Identificazione
/// bloccata a tempo indeterminato invece di finire `fallita` (nessun retry,
/// deciso su #53).
const comicVineTimeout = Duration(seconds: 45);

/// Un risultato della ricerca `/search?resources=issue` di ComicVine — solo i
/// campi rilevanti per lo scoring dei candidati (algoritmo deciso su #52:
/// `volume.name`/`name`/`issueNumber` per il segnale testuale, `image` per
/// il confronto visivo) più `siteDetailUrl`, richiesto in UI per
/// l'attribuzione a Comic Vine imposta dalla licenza (vedi
/// `docs/research/comics-external-database.md` §1.3).
class ComicVineIssueMatch {
  const ComicVineIssueMatch({
    required this.id,
    required this.name,
    required this.issueNumber,
    required this.volumeName,
    required this.coverImageUrl,
    required this.siteDetailUrl,
  });

  final int id;
  final String? name;
  final String? issueNumber;
  final String? volumeName;
  final String? coverImageUrl;
  final String siteDetailUrl;
}

/// Una chiamata all'API ComicVine fallita o con risposta inattesa (rete,
/// HTTP non-2xx, o `status_code` diverso da `1` — inclusi eventuali blocchi
/// temporanei per rate limit: ComicVine non documenta un codice specifico
/// per questo caso, solo "temporary blocks to resources", quindi viene
/// gestito come ogni altro `status_code` di errore invece di essere
/// distinto artificialmente, vedi ricerca #51 §1.2).
class ComicVineException implements Exception {
  ComicVineException(this.message);

  final String message;

  @override
  String toString() => 'ComicVineException: $message';
}

/// Interfaccia del client ComicVine, database esterno di fallback per
/// l'Identificazione del fumetto (§6.3, deciso su #51) — dedicata per poter
/// iniettare un fake nei test del matching (#52), stesso pattern di
/// `CoverAnalysisClient`.
abstract interface class ComicVineClient {
  /// Cerca fra le issue di ComicVine a partire dai campi OCR disponibili di
  /// un'Analisi Copertina. Ricerca testuale libera su `seriesName`+`title`
  /// quando presenti (nessun campo ISBN/barcode nella risorsa `issue`, vedi
  /// ricerca #51); se entrambi sono `null`, fallback su
  /// `issueNumberLabel`+`publisher` (stesso trattamento dei campi mancanti
  /// di #52). Se anche questi sono `null`, non viene fatta alcuna chiamata.
  Future<List<ComicVineIssueMatch>> cercaIssue({
    required String? title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
  });
}

/// Chiama `GET /search?resources=issue` dell'API REST di ComicVine (deciso
/// su #51, nessun SDK Dart ufficiale). Una singola chiamata per
/// Identificazione, come deciso su #52 — nessuna ricerca in due passaggi via
/// `/volumes`.
class ComicVineHttpClient implements ComicVineClient {
  ComicVineHttpClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  Future<List<ComicVineIssueMatch>> cercaIssue({
    required String? title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
  }) async {
    final query = _buildQuery(
      title: title,
      seriesName: seriesName,
      issueNumberLabel: issueNumberLabel,
      publisher: publisher,
    );
    if (query.isEmpty) return const [];

    final uri = Uri.parse(_searchUrl).replace(
      queryParameters: {
        'api_key': ComicVineApiConfig.apiKey,
        'format': 'json',
        'resources': 'issue',
        'query': query,
        'field_list': _fieldList,
      },
    );

    final http.Response response;
    try {
      response = await _httpClient.get(uri).timeout(comicVineTimeout);
    } on Object catch (e) {
      throw ComicVineException("Chiamata all'API ComicVine fallita: $e");
    }

    // La risposta è sempre JSON/UTF-8: `response.body` indovina la codifica
    // dal charset del content-type e cade su Latin-1 corrompendo i caratteri
    // non ASCII (stesso motivo di `ClaudeCoverAnalysisClient`).
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      throw ComicVineException('ComicVine API ${response.statusCode}: $responseBody');
    }

    return _leggiRisposta(responseBody);
  }

  List<ComicVineIssueMatch> _leggiRisposta(String responseBody) {
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final statusCode = body['status_code'] as int?;
      if (statusCode != 1) {
        throw ComicVineException('ComicVine status_code $statusCode: ${body['error']}');
      }

      final results = (body['results'] as List<dynamic>).cast<Map<String, dynamic>>();
      return results.map(_leggiIssue).toList();
    } on ComicVineException {
      rethrow;
    } on Object catch (e) {
      throw ComicVineException('Risposta ComicVine inattesa: $e');
    }
  }

  ComicVineIssueMatch _leggiIssue(Map<String, dynamic> issue) {
    final volume = issue['volume'] as Map<String, dynamic>?;
    final image = issue['image'] as Map<String, dynamic>?;

    return ComicVineIssueMatch(
      id: issue['id'] as int,
      name: issue['name'] as String?,
      issueNumber: issue['issue_number'] as String?,
      volumeName: volume?['name'] as String?,
      coverImageUrl: image?['medium_url'] as String?,
      siteDetailUrl: issue['site_detail_url'] as String,
    );
  }
}

String _buildQuery({
  required String? title,
  required String? seriesName,
  required String? issueNumberLabel,
  required String? publisher,
}) {
  final primari = _campiNonVuoti([seriesName, title]);
  if (primari.isNotEmpty) return primari.join(' ');

  return _campiNonVuoti([issueNumberLabel, publisher]).join(' ');
}

List<String> _campiNonVuoti(List<String?> campi) =>
    campi.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
