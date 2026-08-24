import 'dart:typed_data';

/// Il prompt di estrazione (§6.1 OCR + §6.2 computer vision), condiviso fra i
/// provider AI supportati (Claude, OpenAI, ...) perché deve restituire
/// esattamente gli stessi campi con la stessa semantica — un prompt diverso
/// per provider farebbe divergere silenziosamente i risultati. Elenca
/// esplicitamente tutti i campi richiesti, l'istruzione di restituire
/// coordinate in pixel assolute (non normalizzate — Claude le gestisce
/// peggio, vedi ricerca #28) per la posizione del testo, e di ammettere
/// incertezza sui campi di computer vision invece di indovinare
/// (raccomandazione della documentazione ufficiale sulla riduzione delle
/// allucinazioni, vedi ricerca #47).
const coverAnalysisPrompt =
    'Analizza la copertina di questo fumetto ed estrai i campi richiesti '
    'dallo schema. Se un campo non è leggibile sulla copertina, restituisci '
    'null invece di indovinare. Per ogni elemento di testo rilevante '
    '(titolo, numero, editore, collana, prezzo, barcode) indica la '
    'posizione qualitativa e, se stimabile, il bounding box in coordinate '
    'pixel assolute [x1, y1, x2, y2] (angolo in alto a sinistra e in basso '
    "a destra) rispetto all'immagine ricevuta. Riporta releaseDate "
    "esattamente come stampato sulla copertina (es. 'dicembre 2010'), senza "
    'normalizzarlo in una data ISO. pageCount è il numero di pagine se '
    'riportato in copertina o su un\'etichetta di prezzo/formato. language è '
    "la lingua del testo di copertina (es. 'italiano'). color è "
    "'a colori' o 'bianco e nero' se determinabile dalla copertina stessa. "
    'issn è il codice ISSN della collana/testata periodica se presente, '
    'distinto dal barcode EAN. Per characters, '
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

/// Lo schema JSON dei campi estratti (structured outputs, deciso su #28,
/// esteso su #47/#49), condiviso fra i provider per lo stesso motivo del
/// prompt: ogni provider lo incapsula nel proprio formato di richiesta
/// (`output_config.format` per Claude, `text.format` per OpenAI), ma
/// l'oggetto schema — proprietà, `required`, `additionalProperties: false`
/// — resta identico. Copre titolo, numero, editore, collana, autori, ISBN,
/// barcode, prezzo, codici identificativi, posizione del testo (OCR, §6.1)
/// e personaggi, loghi riconosciuti, stile copertina, elementi visivi
/// caratteristici (computer vision, §6.2). `additionalProperties: false` su
/// ogni oggetto e ogni proprietà in `required` sono richiesti sia dalle
/// structured outputs di Claude sia dallo strict mode di OpenAI; niente
/// vincoli di lunghezza/numerici, non supportati da Claude.
const Map<String, Object?> coverAnalysisJsonSchema = {
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
    'releaseDate': {
      'type': ['string', 'null'],
    },
    'pageCount': {
      'type': ['integer', 'null'],
    },
    'language': {
      'type': ['string', 'null'],
    },
    'color': {
      'type': ['string', 'null'],
    },
    'issn': {
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
    'releaseDate',
    'pageCount',
    'language',
    'color',
    'issn',
    'identifierCodes',
    'textElements',
    'characters',
    'coverStyleTags',
    'visualElementTags',
    'recognizedPublisherLogo',
    'recognizedSeriesLogo',
  ],
  'additionalProperties': false,
};

/// Il risultato grezzo dell'estrazione OCR + computer vision di una
/// copertina (§6.1, §6.2), indipendente dal provider AI che l'ha prodotto.
/// Campi letti così come restituiti dal modello, non parsati né verificati
/// (il parsing verso Opera/Edizione/Serie è §6.3, fuori scope). [raw] è
/// l'intero oggetto JSON decodificato, preservato per i campi che lo schema
/// Drift (#31, #48) non promuove a colonna (autori, codici identificativi,
/// posizione del testo).
class CoverAnalysisResult {
  const CoverAnalysisResult({
    required this.title,
    required this.issueNumberLabel,
    required this.publisher,
    required this.seriesName,
    required this.isbn,
    required this.barcode,
    required this.price,
    required this.releaseDate,
    required this.pageCount,
    required this.language,
    required this.color,
    required this.issn,
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
  final String? releaseDate;
  final int? pageCount;
  final String? language;
  final String? color;
  final String? issn;
  final List<String> characters;
  final List<String> coverStyleTags;
  final List<String> visualElementTags;
  final String? recognizedPublisherLogo;
  final String? recognizedSeriesLogo;
  final Map<String, dynamic> raw;
}

/// Una chiamata a un provider AI fallita o con risposta inattesa (rete, HTTP
/// non-2xx, rifiuto del modello, JSON non conforme allo schema richiesto) —
/// indipendente dal provider che l'ha sollevata.
class CoverAnalysisException implements Exception {
  CoverAnalysisException(this.message);

  final String message;

  @override
  String toString() => 'CoverAnalysisException: $message';
}

/// Interfaccia comune dei client dei provider AI (Claude, OpenAI, ...)
/// usati dalla pipeline di Analisi Copertina (§6.1, §6.2) — il provider
/// effettivo è selezionato a build-time, vedi
/// `CoverAnalysisProviderConfig`/`providers.dart`. Nessuna UI per la scelta
/// (fuori scope della mappa #46).
abstract interface class CoverAnalysisClient {
  Future<CoverAnalysisResult> estraiCopertina(Uint8List immagineJpeg);
}

/// Timeout della chiamata HTTP al provider AI, condiviso fra i client
/// (Claude, OpenAI, ...): senza un timeout esplicito, una richiesta che non
/// riceve mai risposta lascia la Scansione bloccata a tempo indeterminato
/// invece di finire `fallita` e sbloccare il resto del batch (nessun retry
/// automatico, vedi `StatoAnalisiCopertina`).
const coverAnalysisTimeout = Duration(seconds: 45);
