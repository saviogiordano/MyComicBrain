import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/errore_configurazione.dart';

/// `response_format` della Chat Completions API (structured outputs, strict
/// mode): incapsula lo schema condiviso [coverAnalysisJsonSchema]. Stesso
/// formato di `OpenRouterCoverAnalysisClient` — è quello effettivamente
/// esposto dai server locali OpenAI-compatible (Ollama, LM Studio: endpoint
/// `/v1/chat/completions`, non la Responses API più recente usata da
/// `OpenAiCoverAnalysisClient` verso `api.openai.com`, non ancora comune fra
/// questi server).
const Map<String, Object?> _responseFormat = {
  'type': 'json_schema',
  'json_schema': {
    'name': 'cover_analysis',
    'strict': true,
    'schema': coverAnalysisJsonSchema,
  },
};

/// Chiama un endpoint locale OpenAI-compatible (`POST {urlLocale}/chat/completions`
/// — Ollama, LM Studio o analoghi) per estrarre i campi leggibili (§6.1) e di
/// computer vision (§6.2) di una copertina. Stesso prompt/schema condivisi
/// (vedi `cover_analysis_client.dart`) per restituire risultati comparabili.
/// URL, modello (testo libero, nessun default) e API key (opzionale — molti
/// server locali non richiedono autenticazione) letti a runtime da
/// [SettingsRepository] (§12, deciso su #103).
class LocaleCoverAnalysisClient implements CoverAnalysisClient {
  LocaleCoverAnalysisClient({
    SettingsRepository? settingsRepository,
    http.Client? httpClient,
  }) : _settingsRepository = settingsRepository,
       _httpClient = httpClient ?? http.Client();

  final SettingsRepository? _settingsRepository;
  final http.Client _httpClient;

  /// Legge URL, modello e (opzionalmente) API key da [SettingsRepository],
  /// sollevando [CoverAnalysisException] col prefisso
  /// [prefissoConfigurazioneMancante] (§12, deciso su #108) se manca l'URL o
  /// il modello — a differenza di Claude/OpenAI/OpenRouter l'API key resta
  /// facoltativa (molti server locali non la richiedono, deciso su #103).
  /// Condiviso fra [estraiCopertina] e [verificaConnessione].
  Future<({String url, String modello, String? apiKey})>
  _configurazione() async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw CoverAnalysisException(
        '${prefissoConfigurazioneMancante}Nessun URL configurato per il provider Locale nelle Impostazioni.',
      );
    }
    final url = settingsRepository.urlLocale(RuoloProviderAi.visivo);
    if (url == null || url.isEmpty) {
      throw CoverAnalysisException(
        '${prefissoConfigurazioneMancante}Nessun URL configurato per il provider Locale nelle Impostazioni.',
      );
    }
    final modello =
        settingsRepository.modello(RuoloProviderAi.visivo, AiProvider.locale) ??
        AiProvider.locale.modelloDefault(RuoloProviderAi.visivo);
    if (modello.isEmpty) {
      throw CoverAnalysisException(
        '${prefissoConfigurazioneMancante}Nessun modello configurato per il provider Locale nelle Impostazioni.',
      );
    }
    final apiKey = await settingsRepository.apiKeyAi(
      RuoloProviderAi.visivo,
      AiProvider.locale,
    );
    return (url: url, modello: modello, apiKey: apiKey);
  }

  Uri _endpoint(String url) {
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return Uri.parse('$base/chat/completions');
  }

  Map<String, String> _headers(String? apiKey) => {
    'content-type': 'application/json',
    if (apiKey != null && apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
  };

  @override
  Future<CoverAnalysisResult> estraiCopertina(Uint8List immagineJpeg) async {
    final (:url, :modello, :apiKey) = await _configurazione();

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            _endpoint(url),
            headers: _headers(apiKey),
            body: jsonEncode({
              'model': modello,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': coverAnalysisPrompt},
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url':
                            'data:image/jpeg;base64,${base64Encode(immagineJpeg)}',
                      },
                    },
                  ],
                },
              ],
              'response_format': _responseFormat,
            }),
          )
          .timeout(coverAnalysisTimeout);
    } on Object catch (e) {
      throw CoverAnalysisException(
        'Chiamata al provider Locale fallita: $e',
      );
    }

    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      throw CoverAnalysisException(
        'Provider Locale ${response.statusCode}: $responseBody',
      );
    }

    return _leggiRisposta(responseBody);
  }

  /// Chiamata minima (nessuna immagine né schema strutturato) allo stesso
  /// endpoint di [estraiCopertina]: verifica che URL, modello e API key (se
  /// impostata) siano validi senza il costo/tempo di un'estrazione vera.
  @override
  Future<void> verificaConnessione() async {
    final (:url, :modello, :apiKey) = await _configurazione();

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            _endpoint(url),
            headers: _headers(apiKey),
            body: jsonEncode({
              'model': modello,
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
              'max_tokens': 16,
            }),
          )
          .timeout(coverAnalysisTimeout);
    } on Object catch (e) {
      throw CoverAnalysisException(
        'Chiamata al provider Locale fallita: $e',
      );
    }

    if (response.statusCode != 200) {
      throw CoverAnalysisException(
        'Provider Locale ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
  }

  CoverAnalysisResult _leggiRisposta(String responseBody) {
    final Map<String, dynamic> extracted;
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>;
      final messaggio =
          (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>;

      // Un rifiuto del modello (structured outputs, strict mode) arriva col
      // campo `refusal` valorizzato e `content` nullo — non è JSON conforme
      // allo schema, va segnalato esplicitamente invece di far fallire il
      // parsing con un errore generico.
      final rifiuto = messaggio['refusal'] as String?;
      if (rifiuto != null && rifiuto.isNotEmpty) {
        throw CoverAnalysisException(
          'Il provider Locale ha rifiutato la richiesta: $rifiuto',
        );
      }

      extracted =
          jsonDecode(messaggio['content'] as String) as Map<String, dynamic>;
    } on CoverAnalysisException {
      rethrow;
    } on Object catch (e) {
      throw CoverAnalysisException('Risposta del provider Locale inattesa: $e');
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
