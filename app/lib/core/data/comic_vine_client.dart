import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/comic_vine_api_config.dart';
import 'package:mycomicbrain/core/data/numero_pulito.dart';
import 'package:mycomicbrain/core/data/text_similarity.dart';

const _searchUrl = 'https://comicvine.gamespot.com/api/search/';
const _issuesUrl = 'https://comicvine.gamespot.com/api/issues/';

/// Solo i campi che servono al parsing sotto — economizza la risposta,
/// coerente con la raccomandazione della documentazione ufficiale di fare
/// caching/uso parsimonioso dell'API (rate limit 200 richieste/risorsa/ora,
/// vedi `docs/research/comics-external-database.md` §1.2).
const _fieldList = 'id,name,issue_number,volume,image,site_detail_url';

/// Campi della risorsa `volume` che servono a scegliere quali volumi
/// interrogare per numero (#60): `count_of_issues` è la chiave — un volume
/// con meno albi del numero cercato non può contenerlo, vedi
/// [_ComicVineVolumeCandidate]/[_selezionaVolumi].
const _volumeFieldList = 'id,name,publisher,count_of_issues';

/// Quanti volumi candidati interrogare al massimo per numero (una chiamata
/// `/issues/?filter=volume:...,issue_number:...` per volume, oltre alla
/// chiamata di ricerca volumi) — un tetto per restare ampiamente dentro il
/// rate limit di ComicVine anche quando molti volumi omonimi combaciano per
/// nome (ristampe, ripartenze, edizioni estere della stessa testata).
const _massimoVolumiCandidati = 5;

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
  /// un'Analisi Copertina. Quando `seriesName`/`title` e `issueNumberLabel`
  /// sono entrambi disponibili, cerca prima i volumi che combaciano per nome
  /// e poi filtra per numero al loro interno (vedi
  /// `ComicVineHttpClient` — #60: la ricerca testuale libera sulla risorsa
  /// `issue` da sola non trova quasi mai l'albo giusto in una serie lunga,
  /// perché ComicVine non la ordina per numero). Se `seriesName`/`title`
  /// sono entrambi `null`, o se nessun volume candidato contiene quel
  /// numero, ripiega sulla vecchia ricerca testuale libera su `resources=
  /// issue` (nessun campo ISBN/barcode nella risorsa `issue`, vedi ricerca
  /// #51). Se anche `issueNumberLabel`/`publisher` sono `null`, non viene
  /// fatta alcuna chiamata.
  Future<List<ComicVineIssueMatch>> cercaIssue({
    required String? title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
  });
}

/// Candidato di volume ComicVine (`resources=volume`) da cui poi cercare
/// l'issue per numero — solo i campi che servono a [_selezionaVolumi] e a
/// `ComicVineHttpClient._issuePerVolume`.
class _ComicVineVolumeCandidate {
  const _ComicVineVolumeCandidate({
    required this.id,
    required this.name,
    required this.publisherName,
    required this.countOfIssues,
  });

  final int id;
  final String? name;
  final String? publisherName;
  final int? countOfIssues;
}

/// Chiama l'API REST di ComicVine (deciso su #51, nessun SDK Dart
/// ufficiale). Per numero noto, due passaggi (#60, rivede la scelta "una
/// sola chiamata" di #52 — si è rivelata strutturalmente incapace di
/// trovare albi non recenti di serie lunghe): `GET /search?resources=volume`
/// per trovare i volumi il cui nome combacia, poi `GET /issues?filter=volume:ID,issue_number:NUMERO`
/// — una ricerca per campo esatto, non testuale libera — sui volumi
/// candidati più promettenti. Senza numero (o
/// se il filtro per numero non trova nulla), ripiega sulla vecchia ricerca
/// testuale libera `GET /search?resources=issue`. Nel caso peggiore sono
/// `1 + massimoVolumiCandidati` chiamate per Identificazione, ampiamente
/// dentro il rate limit di ComicVine (200 richieste/risorsa/ora) per un uso
/// hobbistico single-user con fallback solo occasionale su ComicVine.
class ComicVineHttpClient implements ComicVineClient {
  ComicVineHttpClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  Future<List<ComicVineIssueMatch>> cercaIssue({
    required String? title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
  }) async {
    final numeroLabel = numeroPulito(issueNumberLabel);
    final serieQuery = _campiNonVuoti([seriesName, title]).join(' ');

    if (serieQuery.isNotEmpty &&
        numeroLabel != null &&
        numeroLabel.isNotEmpty) {
      final volumi = await _cercaVolumi(serieQuery);
      final candidati = _selezionaVolumi(
        volumi,
        nomeRiferimento: seriesName ?? title,
        publisher: publisher,
        numeroLabel: numeroLabel,
      );

      final risultati = <ComicVineIssueMatch>[];
      for (final volume in candidati) {
        risultati.addAll(
          await _issuePerVolume(volumeId: volume.id, numeroLabel: numeroLabel),
        );
      }
      if (risultati.isNotEmpty) return risultati;
    }

    final query = _buildQuery(
      title: title,
      seriesName: seriesName,
      issueNumberLabel: issueNumberLabel,
      publisher: publisher,
    );
    if (query.isEmpty) return const [];
    return _cercaIssueTestoLibero(query);
  }

  /// `GET /search?resources=volume` — trova i volumi il cui nome combacia
  /// testualmente con [query] (`seriesName`/`title` letti dalla copertina).
  Future<List<_ComicVineVolumeCandidate>> _cercaVolumi(String query) async {
    final uri = Uri.parse(_searchUrl).replace(
      queryParameters: {
        'api_key': ComicVineApiConfig.apiKey,
        'format': 'json',
        'resources': 'volume',
        'query': query,
        'limit': '100',
        'field_list': _volumeFieldList,
      },
    );
    final results = await _getResults(uri);
    return results.map(_leggiVolume).toList();
  }

  /// `GET /issues?filter=volume:<id>,issue_number:<numeroLabel>` — ricerca
  /// per campo esatto (non testo libero) all'interno di un singolo volume
  /// già scelto da [_selezionaVolumi]: a differenza della ricerca testuale
  /// su `resources=issue`, trova l'albo giusto anche in serie con centinaia
  /// di numeri, perché non dipende dall'ordinamento per rilevanza di
  /// ComicVine.
  Future<List<ComicVineIssueMatch>> _issuePerVolume({
    required int volumeId,
    required String numeroLabel,
  }) async {
    final uri = Uri.parse(_issuesUrl).replace(
      queryParameters: {
        'api_key': ComicVineApiConfig.apiKey,
        'format': 'json',
        'filter': 'volume:$volumeId,issue_number:$numeroLabel',
        'field_list': _fieldList,
      },
    );
    final results = await _getResults(uri);
    return results.map(_leggiIssue).toList();
  }

  /// `GET /search?resources=issue` — vecchia ricerca testuale libera (deciso
  /// su #51/#52), tenuta come fallback per i casi che la ricerca per volume
  /// non copre: nessun numero leggibile, o nessun volume candidato che lo
  /// contiene (es. speciali/annual non allineati alla numerazione regolare).
  Future<List<ComicVineIssueMatch>> _cercaIssueTestoLibero(String query) async {
    final uri = Uri.parse(_searchUrl).replace(
      queryParameters: {
        'api_key': ComicVineApiConfig.apiKey,
        'format': 'json',
        'resources': 'issue',
        'query': query,
        'field_list': _fieldList,
      },
    );
    final results = await _getResults(uri);
    return results.map(_leggiIssue).toList();
  }

  Future<List<Map<String, dynamic>>> _getResults(Uri uri) async {
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
      throw ComicVineException(
        'ComicVine API ${response.statusCode}: $responseBody',
      );
    }

    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final statusCode = body['status_code'] as int?;
      if (statusCode != 1) {
        throw ComicVineException(
          'ComicVine status_code $statusCode: ${body['error']}',
        );
      }
      return (body['results'] as List<dynamic>).cast<Map<String, dynamic>>();
    } on ComicVineException {
      rethrow;
    } on Object catch (e) {
      throw ComicVineException('Risposta ComicVine inattesa: $e');
    }
  }

  _ComicVineVolumeCandidate _leggiVolume(Map<String, dynamic> volume) =>
      _ComicVineVolumeCandidate(
        id: volume['id'] as int,
        name: volume['name'] as String?,
        publisherName:
            (volume['publisher'] as Map<String, dynamic>?)?['name'] as String?,
        countOfIssues: volume['count_of_issues'] as int?,
      );

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

/// Sceglie fino a [_massimoVolumiCandidati] volumi da interrogare per
/// numero, fra quelli trovati da `_cercaVolumi` (#60). Ordina per un
/// punteggio che combina:
///
/// 1. **Somiglianza testuale** nome+editore rispetto ai campi letti dalla
///    copertina — il segnale dominante, serve a scartare testate diverse.
/// 2. **Idoneità per numero** (`count_of_issues` vs. il numero cercato) —
///    un *bonus/penalità morbido*, non un'esclusione: un `count_of_issues`
///    inferiore al numero cercato rende improbabile ma non impossibile che
///    il volume lo contenga (numerazioni "legacy" con salti/rinumerazioni —
///    es. *The Amazing Spider-Man* 1963, `count_of_issues` 651, contiene
///    comunque il #700 — verificato dal vivo). Un'esclusione rigida
///    scarterebbe per errore proprio il volume corretto in questi casi;
///    la penalità morbida lo demota senza eliminarlo, mentre resta forte
///    abbastanza da far vincere il volume giusto su ripartenze recenti
///    omonime con pochissimi albi (es. una ripartenza da 20 albi per un
///    #135 cercato). Un `count_of_issues` mancante è neutro (né bonus né
///    penalità — dato non garantito da ComicVine).
List<_ComicVineVolumeCandidate> _selezionaVolumi(
  List<_ComicVineVolumeCandidate> volumi, {
  required String? nomeRiferimento,
  required String? publisher,
  required String numeroLabel,
}) {
  final numero = int.tryParse(numeroLabel);

  double idoneitaPerNumero(_ComicVineVolumeCandidate v) {
    if (numero == null || numero <= 0 || v.countOfIssues == null) return 1;
    if (v.countOfIssues! >= numero) return 1;
    return v.countOfIssues! / numero;
  }

  double punteggio(_ComicVineVolumeCandidate v) {
    final simNome = nomeRiferimento == null || nomeRiferimento.trim().isEmpty
        ? 0.0
        : similaritaTestuale(nomeRiferimento, v.name ?? '');
    final simTestuale =
        publisher == null || publisher.trim().isEmpty || v.publisherName == null
        ? simNome
        : simNome * 0.7 + similaritaTestuale(publisher, v.publisherName!) * 0.3;
    return simTestuale * 0.6 + idoneitaPerNumero(v) * 0.4;
  }

  final ordinati = [...volumi]
    ..sort((a, b) => punteggio(b).compareTo(punteggio(a)));
  return ordinati.take(_massimoVolumiCandidati).toList();
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

List<String> _campiNonVuoti(List<String?> campi) => campi
    .whereType<String>()
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();
