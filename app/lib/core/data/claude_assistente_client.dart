import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';

const _apiUrl = 'https://api.anthropic.com/v1/messages';
const _anthropicVersion = '2023-06-01';

/// Numero massimo di token della risposta finale — l'Assistente (§10)
/// produce solo testo colloquiale, mai un blocco lungo: 1024 è ampiamente
/// sufficiente e limita il costo di una conversazione persistita
/// indefinitamente (#122).
const _maxTokens = 1024;

Map<String, Object?> _toolClaude(AssistenteTool tool) => {
  'name': tool.nome,
  'description': tool.descrizione,
  'input_schema': tool.parametri,
};

/// Chiama l'endpoint `POST /v1/messages` di Claude come Provider AI
/// Testuale (§10, ruolo [RuoloProviderAi.testuale], deciso su ADR-0001),
/// gestendo in autonomia il round-trip di tool-calling (`tool_use`/
/// `tool_result`) fino a una risposta testuale finale o
/// [assistenteMaxRoundTool]. Nessun SDK Dart ufficiale (stessa scelta di
/// [ClaudeCoverAnalysisClient]): client HTTP generico verso l'API REST. API
/// key e modello letti a runtime da [SettingsRepository].
class ClaudeAssistenteClient implements AssistenteClient {
  ClaudeAssistenteClient({
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
      AiProvider.claude,
    );
    if (apiKey == null || apiKey.isEmpty) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Nessuna API key configurata per Claude (ruolo Testuale) nelle '
        'Impostazioni.',
      );
    }
    final modello =
        settingsRepository.modello(
          RuoloProviderAi.testuale,
          AiProvider.claude,
        ) ??
        AiProvider.claude.modelloDefault(RuoloProviderAi.testuale);
    return (apiKey: apiKey, modello: modello);
  }

  Map<String, String> _headers(String apiKey) => {
    'x-api-key': apiKey,
    'anthropic-version': _anthropicVersion,
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
      for (final turno in storico)
        {
          'role': turno.ruolo == RuoloMessaggio.utente ? 'user' : 'assistant',
          'content': turno.testo,
        },
    ];

    for (var round = 0; round <= assistenteMaxRoundTool; round++) {
      final body = await _postMessages(apiKey, modello, messages);
      final content = (body['content'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final toolUse = content
          .where((c) => c['type'] == 'tool_use')
          .toList();
      if (toolUse.isEmpty) {
        final testo = content.firstWhere(
          (c) => c['type'] == 'text',
          orElse: () => const <String, dynamic>{},
        );
        if (testo.isEmpty) {
          throw AssistenteException(
            SottotipoSistema.erroreProvider,
            'Risposta Claude senza testo: $body',
          );
        }
        return testo['text'] as String;
      }

      final risultati = <Map<String, Object?>>[];
      for (final blocco in toolUse) {
        final esito = await eseguiTool(
          blocco['name'] as String,
          (blocco['input'] as Map<String, dynamic>?) ?? const {},
        );
        risultati.add({
          'type': 'tool_result',
          'tool_use_id': blocco['id'],
          'content': jsonEncode(esito),
        });
      }

      messages = [
        ...messages,
        {'role': 'assistant', 'content': content},
        {'role': 'user', 'content': risultati},
      ];
    }

    throw AssistenteException(
      SottotipoSistema.erroreProvider,
      'Superato il numero massimo di round di tool-calling '
      '($assistenteMaxRoundTool).',
    );
  }

  Future<Map<String, dynamic>> _postMessages(
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
              'max_tokens': _maxTokens,
              'system': assistentePromptSistema,
              'tools': [for (final tool in assistenteTools) _toolClaude(tool)],
              'messages': messages,
            }),
          )
          .timeout(assistenteTimeout);
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreRete,
        "Chiamata all'API Claude fallita: $e",
      );
    }

    final responseBody = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Claude API ${response.statusCode}: $responseBody',
      );
    }
    try {
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Risposta Claude inattesa: $e',
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
              'max_tokens': 16,
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
            }),
          )
          .timeout(assistenteTimeout);
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreRete,
        "Chiamata all'API Claude fallita: $e",
      );
    }

    if (response.statusCode != 200) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Claude API ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
  }
}
