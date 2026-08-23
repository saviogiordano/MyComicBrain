import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/claude_api_config.dart';

const _apiUrl = 'https://api.anthropic.com/v1/messages';
const _anthropicVersion = '2023-06-01';
const _model = 'claude-sonnet-5';

/// Il prompt di estrazione (§6.1 OCR + §6.2 computer vision, esteso su #49):
/// elenca esplicitamente tutti i campi richiesti dai due requisiti,
/// includendo l'istruzione di restituire coordinate in pixel assolute (non
/// normalizzate — Claude le gestisce peggio, vedi ricerca #28) per la
/// posizione del testo, e di ammettere incertezza sui campi di computer
/// vision invece di indovinare (raccomandazione della documentazione
/// ufficiale sulla riduzione delle allucinazioni, vedi ricerca #47).
const _promptEstrazione =
    'Analizza la copertina di questo fumetto ed estrai i campi richiesti '
    'dallo schema. Se un campo non è leggibile sulla copertina, restituisci '
    'null invece di indovinare. Per ogni elemento di testo rilevante '
    '(titolo, numero, editore, collana, prezzo, barcode) indica la '
    'posizione qualitativa e, se stimabile, il bounding box in coordinate '
    'pixel assolute [x1, y1, x2, y2] (angolo in alto a sinistra e in basso '
    "a destra) rispetto all'immagine ricevuta. Per characters, "
    'coverStyleTags e visualElementTags restituisci una lista vuota se non '
    'riesci a riconoscere alcun elemento con sufficiente sicurezza — non '
    'includere elementi di cui non sei ragionevolmente certo. '
    'coverStyleTags descrive lo stile/genere artistico o la tipologia '
    "editoriale della copertina nel suo complesso (es. 'manga', 'stile "
    "realistico', 'variant cover'); visualElementTags elenca elementi "
    'visivi concreti e specifici presenti su questa copertina che non '
    "descrivono uno stile generale (es. 'sfondo con esplosione', 'cornice "
    "dorata decorata') — non ripetere lo stesso concetto in entrambe le "
    'liste. Per recognizedPublisherLogo/recognizedSeriesLogo restituisci '
    'null se il logo non è visivamente riconoscibile o non sei sicuro.';

const _posizioniQualitative = [
  'alto',
  'alto-sinistra',
  'alto-destra',
  'centro',
  'basso',
  'basso-sinistra',
  'basso-destra',
];

/// Schema JSON per `output_config.format` (structured outputs, deciso su
/// #28, esteso su #47/#49): copre titolo, numero, editore, collana, autori,
/// ISBN, barcode, prezzo, codici identificativi, posizione del testo (OCR,
/// §6.1) e personaggi, loghi riconosciuti, stile copertina, elementi visivi
/// caratteristici (computer vision, §6.2). Ogni oggetto ha
/// `additionalProperties: false` — richiesto dalle structured outputs di
/// Claude; niente vincoli di lunghezza/numerici, non supportati.
const Map<String, Object?> _jsonSchemaFormat = {
  'type': 'json_schema',
  'schema': {
    'type': 'object',
    'properties': {
      'title': {
        'type': ['string', 'null'],
      },
      'issueNumberLabel': {
        'type': ['string', 'null'],
      },
      'publisher': {
        'type': ['string', 'null'],
      },
      'seriesName': {
        'type': ['string', 'null'],
      },
      'authors': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'isbn': {
        'type': ['string', 'null'],
      },
      'barcode': {
        'type': ['string', 'null'],
      },
      'price': {
        'type': ['string', 'null'],
      },
      'identifierCodes': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'textElements': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'qualitativePosition': {
              'type': 'string',
              'enum': _posizioniQualitative,
            },
            'boundingBoxPixel': {
              'type': ['array', 'null'],
              'items': {'type': 'integer'},
            },
          },
          'required': ['label', 'qualitativePosition', 'boundingBoxPixel'],
          'additionalProperties': false,
        },
      },
      'characters': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'coverStyleTags': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'visualElementTags': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'recognizedPublisherLogo': {
        'type': ['string', 'null'],
      },
      'recognizedSeriesLogo': {
        'type': ['string', 'null'],
      },
    },
    'required': [
      'title',
      'issueNumberLabel',
      'publisher',
      'seriesName',
      'authors',
      'isbn',
      'barcode',
      'price',
      'identifierCodes',
      'textElements',
      'characters',
      'coverStyleTags',
      'visualElementTags',
      'recognizedPublisherLogo',
      'recognizedSeriesLogo',
    ],
    'additionalProperties': false,
  },
};

/// Il risultato grezzo dell'estrazione OCR + computer vision di una
/// copertina (§6.1, §6.2): campi letti così come restituiti da Claude, non
/// parsati né verificati (il parsing verso Opera/Edizione/Serie è §6.3,
/// fuori scope). [raw] è l'intero oggetto JSON decodificato, preservato per
/// i campi che lo schema Drift (#31, #48) non promuove a colonna (autori,
/// codici identificativi, posizione del testo).
class ClaudeCoverAnalysisResult {
  const ClaudeCoverAnalysisResult({
    required this.title,
    required this.issueNumberLabel,
    required this.publisher,
    required this.seriesName,
    required this.isbn,
    required this.barcode,
    required this.price,
    required this.characters,
    required this.coverStyleTags,
    required this.visualElementTags,
    required this.recognizedPublisherLogo,
    required this.recognizedSeriesLogo,
    required this.raw,
  });

  final String? title;
  final String? issueNumberLabel;
  final String? publisher;
  final String? seriesName;
  final String? isbn;
  final String? barcode;
  final String? price;
  final List<String> characters;
  final List<String> coverStyleTags;
  final List<String> visualElementTags;
  final String? recognizedPublisherLogo;
  final String? recognizedSeriesLogo;
  final Map<String, dynamic> raw;
}

/// Una chiamata all'API Claude fallita o con risposta inattesa (rete, HTTP
/// non-2xx, JSON non conforme allo schema richiesto).
class ClaudeCoverAnalysisException implements Exception {
  ClaudeCoverAnalysisException(this.message);

  final String message;

  @override
  String toString() => 'ClaudeCoverAnalysisException: $message';
}

/// Chiama l'endpoint `POST /v1/messages` di Claude per estrarre i campi
/// leggibili (§6.1) e di computer vision (§6.2) di una copertina. Nessun SDK
/// Dart ufficiale (ricerca #28): client HTTP generico verso l'API REST.
class ClaudeCoverAnalysisClient {
  ClaudeCoverAnalysisClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<ClaudeCoverAnalysisResult> estraiCopertina(Uint8List immagineJpeg) async {
    final http.Response response;
    try {
      response = await _httpClient.post(
        Uri.parse(_apiUrl),
        headers: {
          'x-api-key': ClaudeApiConfig.apiKey,
          'anthropic-version': _anthropicVersion,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 1024,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': 'image/jpeg',
                    'data': base64Encode(immagineJpeg),
                  },
                },
                {'type': 'text', 'text': _promptEstrazione},
              ],
            },
          ],
          'output_config': {'format': _jsonSchemaFormat},
        }),
      );
    } on Object catch (e) {
      throw ClaudeCoverAnalysisException("Chiamata all'API Claude fallita: $e");
    }

    // La risposta è sempre JSON/UTF-8 (RFC 8259): `response.body` indovina
    // la codifica dal charset del content-type, assente sulle risposte di
    // Anthropic, e cade su Latin-1 corrompendo i caratteri non ASCII.
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      throw ClaudeCoverAnalysisException('Claude API ${response.statusCode}: $responseBody');
    }

    return _leggiRisposta(responseBody);
  }

  ClaudeCoverAnalysisResult _leggiRisposta(String responseBody) {
    final Map<String, dynamic> extracted;
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final content = body['content'] as List<dynamic>;
      final blocco = content.cast<Map<String, dynamic>>().firstWhere(
        (b) => b['type'] == 'text',
      );
      extracted = jsonDecode(blocco['text'] as String) as Map<String, dynamic>;
    } on Object catch (e) {
      throw ClaudeCoverAnalysisException('Risposta Claude inattesa: $e');
    }

    return ClaudeCoverAnalysisResult(
      title: extracted['title'] as String?,
      issueNumberLabel: extracted['issueNumberLabel'] as String?,
      publisher: extracted['publisher'] as String?,
      seriesName: extracted['seriesName'] as String?,
      isbn: extracted['isbn'] as String?,
      barcode: extracted['barcode'] as String?,
      price: extracted['price'] as String?,
      characters: (extracted['characters'] as List<dynamic>).cast<String>(),
      coverStyleTags: (extracted['coverStyleTags'] as List<dynamic>).cast<String>(),
      visualElementTags: (extracted['visualElementTags'] as List<dynamic>).cast<String>(),
      recognizedPublisherLogo: extracted['recognizedPublisherLogo'] as String?,
      recognizedSeriesLogo: extracted['recognizedSeriesLogo'] as String?,
      raw: extracted,
    );
  }
}
