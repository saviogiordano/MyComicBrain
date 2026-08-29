import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';

const _apiUrl = 'https://openrouter.ai/api/v1/chat/completions';

Map<String, Object?> _toolOpenAiCompat(AssistenteTool tool) => {
  'type': 'function',
  'function': {
    'name': tool.nome,
    'description': tool.descrizione,
    'parameters': tool.parametri,
  },
};

/// Chiama la Chat Completions API di OpenRouter (`POST /api/v1/chat/completions`,
/// compatibile OpenAI) come Provider AI Testuale (§10, ruolo
/// [RuoloProviderAi.testuale], deciso su ADR-0001), gestendo in autonomia
/// il round-trip di tool-calling (`tool_calls`/messaggi `role: tool`) fino
/// a una risposta testuale finale o [assistenteMaxRoundTool]. API key e
/// modello (testo libero, deciso su #103) letti a runtime da
/// [SettingsRepository].
class OpenRouterAssistenteClient implements AssistenteClient {
  OpenRouterAssistenteClient({
    SettingsRepository? settingsRepository,
    http.Client? httpClient,
  }) : _settingsRepository = settingsRepository,
       _httpClient = httpClient ?? http.Client();

  final SettingsRepository? _settingsRepository;
  final http.Client _httpClient;

  Future<({String apiKey, String modello})> _apiKeyEModello() async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Nessuna configurazione Testuale disponibile.',
      );
    }
    final apiKey = await settingsRepository.apiKeyAi(
      RuoloProviderAi.testuale,
      AiProvider.openRouter,
    );
    if (apiKey == null || apiKey.isEmpty) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Nessuna API key configurata per OpenRouter (ruolo Testuale) nelle '
        'Impostazioni.',
      );
    }
    final modello =
        settingsRepository.modello(
          RuoloProviderAi.testuale,
          AiProvider.openRouter,
        ) ??
        AiProvider.openRouter.modelloDefault(RuoloProviderAi.testuale);
    return (apiKey: apiKey, modello: modello);
  }

  Map<String, String> _headers(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
    'content-type': 'application/json',
  };

  @override
  Future<String> chiedi({
    required List<TurnoConversazione> storico,
    required Future<Map<String, Object?>> Function(
      String nomeTool,
      Map<String, Object?> argomenti,
    )
    eseguiTool,
  }) async {
    final (:apiKey, :modello) = await _apiKeyEModello();

    var messages = <Map<String, Object?>>[
      {'role': 'system', 'content': assistentePromptSistema},
      for (final turno in storico)
        {
          'role': turno.ruolo == RuoloMessaggio.utente ? 'user' : 'assistant',
          'content': turno.testo,
        },
    ];

    for (var round = 0; round <= assistenteMaxRoundTool; round++) {
      final body = await _postChatCompletions(apiKey, modello, messages);
      final messaggio =
          ((body['choices'] as List<dynamic>).first
                  as Map<String, dynamic>)['message']
              as Map<String, dynamic>;
      final toolCalls = (messaggio['tool_calls'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>();

      if (toolCalls == null || toolCalls.isEmpty) {
        final testo = messaggio['content'] as String?;
        if (testo == null || testo.isEmpty) {
          throw AssistenteException(
            SottotipoSistema.erroreProvider,
            'Risposta OpenRouter senza testo: $body',
          );
        }
        return testo;
      }

      final risultati = <Map<String, Object?>>[];
      for (final call in toolCalls) {
        final function = call['function'] as Map<String, dynamic>;
        final argomenti =
            jsonDecode(function['arguments'] as String)
                as Map<String, dynamic>;
        final esito = await eseguiTool(function['name'] as String, argomenti);
        risultati.add({
          'role': 'tool',
          'tool_call_id': call['id'],
          'content': jsonEncode(esito),
        });
      }

      messages = [...messages, messaggio, ...risultati];
    }

    throw AssistenteException(
      SottotipoSistema.erroreProvider,
      'Superato il numero massimo di round di tool-calling '
      '($assistenteMaxRoundTool).',
    );
  }

  Future<Map<String, dynamic>> _postChatCompletions(
    String apiKey,
    String modello,
    List<Map<String, Object?>> messages,
  ) async {
    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(_apiUrl),
            headers: _headers(apiKey),
            body: jsonEncode({
              'model': modello,
              'messages': messages,
              'tools': [
                for (final tool in assistenteTools) _toolOpenAiCompat(tool),
              ],
            }),
          )
          .timeout(assistenteTimeout);
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreRete,
        "Chiamata all'API OpenRouter fallita: $e",
      );
    }

    final responseBody = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'OpenRouter API ${response.statusCode}: $responseBody',
      );
    }
    try {
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Risposta OpenRouter inattesa: $e',
      );
    }
  }

  @override
  Future<void> verificaConnessione() async {
    final (:apiKey, :modello) = await _apiKeyEModello();

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(_apiUrl),
            headers: _headers(apiKey),
            body: jsonEncode({
              'model': modello,
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
              'max_tokens': 16,
            }),
          )
          .timeout(assistenteTimeout);
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreRete,
        "Chiamata all'API OpenRouter fallita: $e",
      );
    }

    if (response.statusCode != 200) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'OpenRouter API ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
  }
}
