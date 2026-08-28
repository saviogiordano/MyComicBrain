import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/errore_configurazione.dart';

const _apiUrl = 'https://api.openai.com/v1/responses';

/// `text.format` della Responses API di OpenAI (structured outputs, strict
/// mode): incapsula lo schema condiviso [coverAnalysisJsonSchema]. Lo strict
/// mode di OpenAI richiede `additionalProperties: false` su ogni oggetto e
/// ogni proprietà elencata in `required` — lo schema condiviso rispetta già
/// entrambi i vincoli (richiesti anche dalle structured outputs di Claude).
const Map<String, Object?> _textFormat = {
  'type': 'json_schema',
  'name': 'cover_analysis',
  'strict': true,
  'schema': coverAnalysisJsonSchema,
};

/// Chiama la Responses API di OpenAI (`POST /v1/responses`) per estrarre i
/// campi leggibili (§6.1) e di computer vision (§6.2) di una copertina —
/// provider alternativo a Claude, stesso prompt/schema condivisi (vedi
/// `cover_analysis_client.dart`) per restituire risultati comparabili.
/// Nessun SDK Dart ufficiale: client HTTP generico verso l'API REST. API key
/// e modello letti a runtime da [SettingsRepository] (§12, deciso su
/// #101/#102, migrato su #106) — non più a build-time. Modello di default
/// `gpt-5.6-terra` (fascia intermedia, comparabile a `claude-sonnet-5` per
/// rapporto capacità/costo — vision + structured outputs strict mode), vedi
/// `AiProvider.openai.modelloDefault(RuoloProviderAi.visivo)`.
class OpenAiCoverAnalysisClient implements CoverAnalysisClient {
  OpenAiCoverAnalysisClient({
    SettingsRepository? settingsRepository,
    http.Client? httpClient,
  }) : _settingsRepository = settingsRepository,
       _httpClient = httpClient ?? http.Client();

  final SettingsRepository? _settingsRepository;
  final http.Client _httpClient;

  /// Legge API key e modello da [SettingsRepository], sollevando
  /// [CoverAnalysisException] col prefisso [prefissoConfigurazioneMancante]
  /// (§12, deciso su #108) se manca la chiave — condiviso fra
  /// [estraiCopertina] e [verificaConnessione].
  Future<({String apiKey, String modello})> _apiKeyEModello() async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw CoverAnalysisException(
        '${prefissoConfigurazioneMancante}Nessuna API key configurata per OpenAI nelle Impostazioni.',
      );
    }
    final apiKey = await settingsRepository.apiKeyAi(
      RuoloProviderAi.visivo,
      AiProvider.openai,
    );
    if (apiKey == null || apiKey.isEmpty) {
      throw CoverAnalysisException(
        '${prefissoConfigurazioneMancante}Nessuna API key configurata per OpenAI nelle Impostazioni.',
      );
    }
    final modello =
        settingsRepository.modello(RuoloProviderAi.visivo, AiProvider.openai) ??
        AiProvider.openai.modelloDefault(RuoloProviderAi.visivo);
    return (apiKey: apiKey, modello: modello);
  }

  @override
  Future<CoverAnalysisResult> estraiCopertina(Uint8List immagineJpeg) async {
    final (:apiKey, :modello) = await _apiKeyEModello();

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': modello,
              'input': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'input_text', 'text': coverAnalysisPrompt},
                    {
                      'type': 'input_image',
                      'image_url':
                          'data:image/jpeg;base64,${base64Encode(immagineJpeg)}',
                      'detail': 'high',
                    },
                  ],
                },
              ],
              'text': {'format': _textFormat},
            }),
          )
          .timeout(coverAnalysisTimeout);
    } on Object catch (e) {
      throw CoverAnalysisException("Chiamata all'API OpenAI fallita: $e");
    }

    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      throw CoverAnalysisException(
        'OpenAI API ${response.statusCode}: $responseBody',
      );
    }

    return _leggiRisposta(responseBody);
  }

  /// Chiamata minima (nessuna immagine né schema strutturato) allo stesso
  /// endpoint di [estraiCopertina]: verifica che API key e modello siano
  /// validi senza il costo/tempo di un'estrazione vera. `max_output_tokens`
  /// a 16 è il minimo accettato dalla Responses API.
  @override
  Future<void> verificaConnessione() async {
    final (:apiKey, :modello) = await _apiKeyEModello();

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': modello,
              'input': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'input_text', 'text': 'ping'},
                  ],
                },
              ],
              'max_output_tokens': 16,
            }),
          )
          .timeout(coverAnalysisTimeout);
    } on Object catch (e) {
      throw CoverAnalysisException("Chiamata all'API OpenAI fallita: $e");
    }

    if (response.statusCode != 200) {
      throw CoverAnalysisException(
        'OpenAI API ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
  }

  CoverAnalysisResult _leggiRisposta(String responseBody) {
    final Map<String, dynamic> extracted;
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final output = body['output'] as List<dynamic>;
      final messaggio = output.cast<Map<String, dynamic>>().firstWhere(
        (o) => o['type'] == 'message',
      );
      final content = (messaggio['content'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      // Un rifiuto del modello (structured outputs, strict mode) arriva
      // come blocco `refusal` distinto da `output_text` — non è JSON
      // conforme allo schema, va segnalato esplicitamente invece di far
      // fallire il parsing con un errore generico.
      final rifiuto = content.firstWhere(
        (c) => c['type'] == 'refusal',
        orElse: () => const <String, dynamic>{},
      );
      if (rifiuto.isNotEmpty) {
        throw CoverAnalysisException(
          'OpenAI ha rifiutato la richiesta: ${rifiuto['refusal']}',
        );
      }

      final blocco = content.firstWhere((c) => c['type'] == 'output_text');
      extracted = jsonDecode(blocco['text'] as String) as Map<String, dynamic>;
    } on CoverAnalysisException {
      rethrow;
    } on Object catch (e) {
      throw CoverAnalysisException('Risposta OpenAI inattesa: $e');
    }

    return CoverAnalysisResult(
      title: extracted['title'] as String?,
      issueNumberLabel: extracted['issueNumberLabel'] as String?,
      publisher: extracted['publisher'] as String?,
      seriesName: extracted['seriesName'] as String?,
      isbn: extracted['isbn'] as String?,
      barcode: extracted['barcode'] as String?,
      price: extracted['price'] as String?,
      releaseDate: extracted['releaseDate'] as String?,
      year: extracted['year'] as int?,
      pageCount: extracted['pageCount'] as int?,
      language: extracted['language'] as String?,
      color: extracted['color'] as String?,
      issn: extracted['issn'] as String?,
      characters: (extracted['characters'] as List<dynamic>).cast<String>(),
      coverStyleTags: (extracted['coverStyleTags'] as List<dynamic>)
          .cast<String>(),
      visualElementTags: (extracted['visualElementTags'] as List<dynamic>)
          .cast<String>(),
      recognizedPublisherLogo: extracted['recognizedPublisherLogo'] as String?,
      recognizedSeriesLogo: extracted['recognizedSeriesLogo'] as String?,
      printingType: extracted['printingType'] as String?,
      classificazione: extracted['classificazione'] as String?,
      description: extracted['description'] as String?,
      raw: extracted,
    );
  }
}
