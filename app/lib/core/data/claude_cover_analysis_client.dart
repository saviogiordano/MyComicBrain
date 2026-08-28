import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/errore_configurazione.dart';

const _apiUrl = 'https://api.anthropic.com/v1/messages';
const _anthropicVersion = '2023-06-01';

/// `output_config.format` di Claude (structured outputs, deciso su #28):
/// incapsula lo schema condiviso [coverAnalysisJsonSchema].
const Map<String, Object?> _jsonSchemaFormat = {
  'type': 'json_schema',
  'schema': coverAnalysisJsonSchema,
};

/// Chiama l'endpoint `POST /v1/messages` di Claude per estrarre i campi
/// leggibili (§6.1) e di computer vision (§6.2) di una copertina. Nessun SDK
/// Dart ufficiale (ricerca #28): client HTTP generico verso l'API REST.
/// API key e modello letti a runtime da [SettingsRepository] (§12, deciso
/// su #101/#102, migrato su #106) — non più a build-time.
class ClaudeCoverAnalysisClient implements CoverAnalysisClient {
  ClaudeCoverAnalysisClient({
    SettingsRepository? settingsRepository,
    http.Client? httpClient,
  }) : _settingsRepository = settingsRepository,
       _httpClient = httpClient ?? http.Client();

  final SettingsRepository? _settingsRepository;
  final http.Client _httpClient;

  /// Legge API key e modello da [SettingsRepository], sollevando
  /// [CoverAnalysisException] col prefisso [prefissoConfigurazioneMancante]
  /// (§12, deciso su #108: distingue una configurazione mancante da un
  /// fallimento tecnico generico agli occhi della UI) se manca la chiave —
  /// condiviso fra [estraiCopertina] e [verificaConnessione].
  Future<({String apiKey, String modello})> _apiKeyEModello() async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw CoverAnalysisException(
        '${prefissoConfigurazioneMancante}Nessuna API key configurata per Claude nelle Impostazioni.',
      );
    }
    final apiKey = await settingsRepository.apiKeyAi(
      RuoloProviderAi.visivo,
      AiProvider.claude,
    );
    if (apiKey == null || apiKey.isEmpty) {
      throw CoverAnalysisException(
        '${prefissoConfigurazioneMancante}Nessuna API key configurata per Claude nelle Impostazioni.',
      );
    }
    final modello =
        settingsRepository.modello(RuoloProviderAi.visivo, AiProvider.claude) ??
        AiProvider.claude.modelloDefault(RuoloProviderAi.visivo);
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
              'x-api-key': apiKey,
              'anthropic-version': _anthropicVersion,
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': modello,
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
                    {'type': 'text', 'text': coverAnalysisPrompt},
                  ],
                },
              ],
              'output_config': {'format': _jsonSchemaFormat},
            }),
          )
          .timeout(coverAnalysisTimeout);
    } on Object catch (e) {
      throw CoverAnalysisException("Chiamata all'API Claude fallita: $e");
    }

    // La risposta è sempre JSON/UTF-8 (RFC 8259): `response.body` indovina
    // la codifica dal charset del content-type, assente sulle risposte di
    // Anthropic, e cade su Latin-1 corrompendo i caratteri non ASCII.
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      throw CoverAnalysisException(
        'Claude API ${response.statusCode}: $responseBody',
      );
    }

    return _leggiRisposta(responseBody);
  }

  /// Chiamata minima (`max_tokens: 1`, nessuna immagine né schema) allo
  /// stesso endpoint di [estraiCopertina]: verifica che API key e modello
  /// siano validi senza il costo/tempo di un'estrazione vera.
  @override
  Future<void> verificaConnessione() async {
    final (:apiKey, :modello) = await _apiKeyEModello();

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': _anthropicVersion,
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': modello,
              'max_tokens': 1,
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
            }),
          )
          .timeout(coverAnalysisTimeout);
    } on Object catch (e) {
      throw CoverAnalysisException("Chiamata all'API Claude fallita: $e");
    }

    if (response.statusCode != 200) {
      throw CoverAnalysisException(
        'Claude API ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
  }

  CoverAnalysisResult _leggiRisposta(String responseBody) {
    final Map<String, dynamic> extracted;
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final content = body['content'] as List<dynamic>;
      final blocco = content.cast<Map<String, dynamic>>().firstWhere(
        (b) => b['type'] == 'text',
      );
      extracted = jsonDecode(blocco['text'] as String) as Map<String, dynamic>;
    } on Object catch (e) {
      throw CoverAnalysisException('Risposta Claude inattesa: $e');
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
