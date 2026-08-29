import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';

Map<String, Object?> _toolOpenAiCompat(AssistenteTool tool) => {
  'type': 'function',
  'function': {
    'name': tool.nome,
    'description': tool.descrizione,
    'parameters': tool.parametri,
  },
};

/// Chiama un endpoint locale OpenAI-compatible (`POST {urlLocale}/chat/completions`
/// — Ollama, LM Studio o analoghi) come Provider AI Testuale (§10, ruolo
/// [RuoloProviderAi.testuale], deciso su ADR-0001), gestendo in autonomia il
/// round-trip di tool-calling (`tool_calls`/messaggi `role: tool`) fino a
/// una risposta testuale finale o [assistenteMaxRoundTool]. URL, modello
/// (testo libero, nessun default) e API key (opzionale — molti server
/// locali non richiedono autenticazione) letti a runtime da
/// [SettingsRepository] — stesso trattamento di
/// [LocaleCoverAnalysisClient].
class LocaleAssistenteClient implements AssistenteClient {
  LocaleAssistenteClient({
    SettingsRepository? settingsRepository,
    http.Client? httpClient,
  }) : _settingsRepository = settingsRepository,
       _httpClient = httpClient ?? http.Client();

  final SettingsRepository? _settingsRepository;
  final http.Client _httpClient;

  Future<({String url, String modello, String? apiKey})>
  _configurazione() async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Nessuna configurazione Testuale disponibile.',
      );
    }
    final url = settingsRepository.urlLocale(RuoloProviderAi.testuale);
    if (url == null || url.isEmpty) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Nessun URL configurato per il provider Locale (ruolo Testuale) '
        'nelle Impostazioni.',
      );
    }
    final modello =
        settingsRepository.modello(
          RuoloProviderAi.testuale,
          AiProvider.locale,
        ) ??
        AiProvider.locale.modelloDefault(RuoloProviderAi.testuale);
    if (modello.isEmpty) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Nessun modello configurato per il provider Locale (ruolo Testuale) '
        'nelle Impostazioni.',
      );
    }
    final apiKey = await settingsRepository.apiKeyAi(
      RuoloProviderAi.testuale,
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
  Future<String> chiedi({
    required List<TurnoConversazione> storico,
    required Future<Map<String, Object?>> Function(
      String nomeTool,
      Map<String, Object?> argomenti,
    )
    eseguiTool,
  }) async {
    final (:url, :modello, :apiKey) = await _configurazione();

    var messages = <Map<String, Object?>>[
      {'role': 'system', 'content': assistentePromptSistema},
      for (final turno in storico)
        {
          'role': turno.ruolo == RuoloMessaggio.utente ? 'user' : 'assistant',
          'content': turno.testo,
        },
    ];

    for (var round = 0; round <= assistenteMaxRoundTool; round++) {
      final body = await _postChatCompletions(
        url,
        apiKey,
        modello,
        messages,
      );
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
            'Risposta dal provider Locale senza testo: $body',
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
    String url,
    String? apiKey,
    String modello,
    List<Map<String, Object?>> messages,
  ) async {
    final http.Response response;
    try {
      response = await _httpClient
          .post(
            _endpoint(url),
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
        'Chiamata al provider Locale fallita: $e',
      );
    }

    final responseBody = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Provider Locale ${response.statusCode}: $responseBody',
      );
    }
    try {
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Risposta del provider Locale inattesa: $e',
      );
    }
  }

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
          .timeout(assistenteTimeout);
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreRete,
        'Chiamata al provider Locale fallita: $e',
      );
    }

    if (response.statusCode != 200) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Provider Locale ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
  }
}
