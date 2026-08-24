import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/claude_api_config.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';

const _apiUrl = 'https://api.anthropic.com/v1/messages';
const _anthropicVersion = '2023-06-01';
const _model = 'claude-sonnet-5';

/// `output_config.format` di Claude (structured outputs, deciso su #28):
/// incapsula lo schema condiviso [coverAnalysisJsonSchema].
const Map<String, Object?> _jsonSchemaFormat = {
  'type': 'json_schema',
  'schema': coverAnalysisJsonSchema,
};

/// Chiama l'endpoint `POST /v1/messages` di Claude per estrarre i campi
/// leggibili (§6.1) e di computer vision (§6.2) di una copertina. Nessun SDK
/// Dart ufficiale (ricerca #28): client HTTP generico verso l'API REST.
class ClaudeCoverAnalysisClient implements CoverAnalysisClient {
  ClaudeCoverAnalysisClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  @override
  Future<CoverAnalysisResult> estraiCopertina(Uint8List immagineJpeg) async {
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
                {'type': 'text', 'text': coverAnalysisPrompt},
              ],
            },
          ],
          'output_config': {'format': _jsonSchemaFormat},
        }),
      ).timeout(coverAnalysisTimeout);
    } on Object catch (e) {
      throw CoverAnalysisException("Chiamata all'API Claude fallita: $e");
    }

    // La risposta è sempre JSON/UTF-8 (RFC 8259): `response.body` indovina
    // la codifica dal charset del content-type, assente sulle risposte di
    // Anthropic, e cade su Latin-1 corrompendo i caratteri non ASCII.
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode != 200) {
      throw CoverAnalysisException('Claude API ${response.statusCode}: $responseBody');
    }

    return _leggiRisposta(responseBody);
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
      pageCount: extracted['pageCount'] as int?,
      language: extracted['language'] as String?,
      color: extracted['color'] as String?,
      issn: extracted['issn'] as String?,
      characters: (extracted['characters'] as List<dynamic>).cast<String>(),
      coverStyleTags: (extracted['coverStyleTags'] as List<dynamic>).cast<String>(),
      visualElementTags: (extracted['visualElementTags'] as List<dynamic>).cast<String>(),
      recognizedPublisherLogo: extracted['recognizedPublisherLogo'] as String?,
      recognizedSeriesLogo: extracted['recognizedSeriesLogo'] as String?,
      raw: extracted,
    );
  }
}
