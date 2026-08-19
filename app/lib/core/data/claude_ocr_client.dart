import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/claude_api_config.dart';

const _apiUrl = 'https://api.anthropic.com/v1/messages';
const _anthropicVersion = '2023-06-01';
const _model = 'claude-sonnet-5';

/// Il prompt di estrazione (§6.1): elenca esplicitamente tutti i campi
/// richiesti dal requisito, includendo l'istruzione di restituire
/// coordinate in pixel assolute (non normalizzate — Claude le gestisce
/// peggio, vedi ricerca #28) per la posizione del testo.
const _promptEstrazione =
    'Analizza la copertina di questo fumetto ed estrai i campi richiesti '
    'dallo schema. Se un campo non è leggibile sulla copertina, restituisci '
    'null invece di indovinare. Per ogni elemento di testo rilevante '
    '(titolo, numero, editore, collana, prezzo, barcode) indica la '
    'posizione qualitativa e, se stimabile, il bounding box in coordinate '
    'pixel assolute [x1, y1, x2, y2] (angolo in alto a sinistra e in basso '
    "a destra) rispetto all'immagine ricevuta.";

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
/// #28): copre titolo, numero, editore, collana, autori, ISBN, barcode,
/// prezzo, codici identificativi e posizione del testo. Ogni oggetto ha
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
    ],
    'additionalProperties': false,
  },
};

/// Il risultato grezzo dell'estrazione OCR di una copertina (§6.1): campi
/// letti così come restituiti da Claude, non parsati né verificati (il
/// parsing verso Opera/Edizione/Serie è §6.3, fuori scope). [raw] è
/// l'intero oggetto JSON decodificato, preservato per i campi che lo schema
/// Drift (#31) non promuove a colonna (autori, codici identificativi,
/// posizione del testo).
class ClaudeOcrResult {
  const ClaudeOcrResult({
    required this.title,
    required this.issueNumberLabel,
    required this.publisher,
    required this.seriesName,
    required this.isbn,
    required this.barcode,
    required this.price,
    required this.raw,
  });

  final String? title;
  final String? issueNumberLabel;
  final String? publisher;
  final String? seriesName;
  final String? isbn;
  final String? barcode;
  final String? price;
  final Map<String, dynamic> raw;
}

/// Una chiamata all'API Claude fallita o con risposta inattesa (rete, HTTP
/// non-2xx, JSON non conforme allo schema richiesto).
class ClaudeOcrException implements Exception {
  ClaudeOcrException(this.message);

  final String message;

  @override
  String toString() => 'ClaudeOcrException: $message';
}

/// Chiama l'endpoint `POST /v1/messages` di Claude per estrarre i campi
/// leggibili di una copertina (§6.1). Nessun SDK Dart ufficiale (ricerca
/// #28): client HTTP generico verso l'API REST.
class ClaudeOcrClient {
  ClaudeOcrClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<ClaudeOcrResult> estraiCopertina(Uint8List immagineJpeg) async {
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
      throw ClaudeOcrException("Chiamata all'API Claude fallita: $e");
    }

    // La risposta è sempre JSON/UTF-8 (RFC 8259): `response.body` indovina
    // la codifica dal charset del content-type, assente sulle risposte di
    // Anthropic, e cade su Latin-1 corrompendo i caratteri non ASCII.
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      throw ClaudeOcrException('Claude API ${response.statusCode}: $responseBody');
    }

    return _leggiRisposta(responseBody);
  }

  ClaudeOcrResult _leggiRisposta(String responseBody) {
    final Map<String, dynamic> extracted;
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final content = body['content'] as List<dynamic>;
      final blocco = content.cast<Map<String, dynamic>>().firstWhere(
        (b) => b['type'] == 'text',
      );
      extracted = jsonDecode(blocco['text'] as String) as Map<String, dynamic>;
    } on Object catch (e) {
      throw ClaudeOcrException('Risposta Claude inattesa: $e');
    }

    return ClaudeOcrResult(
      title: extracted['title'] as String?,
      issueNumberLabel: extracted['issueNumberLabel'] as String?,
      publisher: extracted['publisher'] as String?,
      seriesName: extracted['seriesName'] as String?,
      isbn: extracted['isbn'] as String?,
      barcode: extracted['barcode'] as String?,
      price: extracted['price'] as String?,
      raw: extracted,
    );
  }
}
