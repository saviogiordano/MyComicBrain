import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/errore_configurazione.dart';

const _apiUrl = 'https://openrouter.ai/api/v1/chat/completions';

/// `response_format` della Chat Completions API (structured outputs, strict
/// mode): incapsula lo schema condiviso [coverAnalysisJsonSchema]. OpenRouter
/// instrada la richiesta al modello scelto restando compatibile con questo
/// formato OpenAI a prescindere dal modello sottostante (§12, deciso su
/// [Modelli LLM selezionabili per provider e formato/validazione dell'URL per il provider locale](https://github.com/saviogiordano/MyComicBrain/issues/103)).
const Map<String, Object?> _responseFormat = {
  'type': 'json_schema',
  'json_schema': {
    'name': 'cover_analysis',
    'strict': true,
    'schema': coverAnalysisJsonSchema,
  },
};

/// Chiama la Chat Completions API di OpenRouter (`POST /api/v1/chat/completions`,
/// compatibile OpenAI) per estrarre i campi leggibili (§6.1) e di computer
/// vision (§6.2) di una copertina — provider ad accesso aperto al catalogo di
/// modelli, scelto in alternativa a Claude/OpenAI diretti proprio per non
/// limitarsi a un elenco curato (§12, deciso su #103). Stesso prompt/schema
/// condivisi (vedi `cover_analysis_client.dart`) per restituire risultati
/// comparabili. Nessun SDK Dart ufficiale: client HTTP generico verso l'API
/// REST. API key e modello (testo libero, deciso su #103) letti a runtime da
/// [SettingsRepository].
class OpenRouterCoverAnalysisClient implements CoverAnalysisClient {
  OpenRouterCoverAnalysisClient({
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
        '${prefissoConfigurazioneMancante}Nessuna API key configurata per OpenRouter nelle Impostazioni.',
      );
    }
    final apiKey = await settingsRepository.apiKeyAi(AiProvider.openRouter);
    if (apiKey == null || apiKey.isEmpty) {
      throw CoverAnalysisException(
        '${prefissoConfigurazioneMancante}Nessuna API key configurata per OpenRouter nelle Impostazioni.',
      );
    }
    final modello =
        settingsRepository.modello(AiProvider.openRouter) ??
        AiProvider.openRouter.modelloDefault;
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
      throw CoverAnalysisException("Chiamata all'API OpenRouter fallita: $e");
    }

    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      throw CoverAnalysisException(
        'OpenRouter API ${response.statusCode}: $responseBody',
      );
    }

    return _leggiRisposta(responseBody);
  }

  /// Chiamata minima (nessuna immagine né schema strutturato) allo stesso
  /// endpoint di [estraiCopertina]: verifica che API key e modello siano
  /// validi senza il costo/tempo di un'estrazione vera.
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
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
              'max_tokens': 16,
            }),
          )
          .timeout(coverAnalysisTimeout);
    } on Object catch (e) {
      throw CoverAnalysisException("Chiamata all'API OpenRouter fallita: $e");
    }

    if (response.statusCode != 200) {
      throw CoverAnalysisException(
        'OpenRouter API ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
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
          'OpenRouter ha rifiutato la richiesta: $rifiuto',
        );
      }

      extracted =
          jsonDecode(messaggio['content'] as String) as Map<String, dynamic>;
    } on CoverAnalysisException {
      rethrow;
    } on Object catch (e) {
      throw CoverAnalysisException('Risposta OpenRouter inattesa: $e');
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
