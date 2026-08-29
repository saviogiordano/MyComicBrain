import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';

const _apiUrl = 'https://api.openai.com/v1/responses';

/// Converte [AssistenteTool.parametri] nella "strict mode" della Responses
/// API di OpenAI: senza di essa, il modello riempie ogni campo opzionale
/// non usato con un valore fittizio invece di ometterlo (stringa vuota per
/// i campi testo, `0` per un campo intero) — letto come filtro valido da
/// `ComicsRepository.cercaEdizioni`, azzerando i risultati di qualunque
/// domanda (bug osservato: `numero: 0` applicato in AND a ogni ricerca).
/// La strict mode elimina l'ambiguità: ogni proprietà non originariamente
/// obbligatoria diventa nullable (`type: [tipo, 'null']`) mentre l'intero
/// insieme di proprietà passa in `required`, così il modello è forzato a
/// restituire esplicitamente `null` per un campo che non intende valorizzare
/// invece di indovinarne un default.
Map<String, Object?> _toolOpenAi(AssistenteTool tool) {
  final parametri = tool.parametri;
  final proprieta = parametri['properties']! as Map<String, Object?>;
  final obbligatori = ((parametri['required'] as List<Object?>?) ?? const [])
      .cast<String>()
      .toSet();

  final proprietaStrict = {
    for (final entry in proprieta.entries)
      entry.key: obbligatori.contains(entry.key)
          ? entry.value
          : {
              ...entry.value! as Map<String, Object?>,
              'type': [
                (entry.value! as Map<String, Object?>)['type'],
                'null',
              ],
            },
  };

  return {
    'type': 'function',
    'name': tool.nome,
    'description': tool.descrizione,
    'strict': true,
    'parameters': {
      'type': 'object',
      'properties': proprietaStrict,
      'required': proprieta.keys.toList(),
      'additionalProperties': false,
    },
  };
}

/// Chiama la Responses API di OpenAI (`POST /v1/responses`) come Provider
/// AI Testuale (§10, ruolo [RuoloProviderAi.testuale], deciso su ADR-0001),
/// gestendo in autonomia il round-trip di tool-calling (`function_call`/
/// `function_call_output`) fino a una risposta testuale finale o
/// [assistenteMaxRoundTool]. Nessuno stato lato server fra le chiamate
/// (nessun `previous_response_id`): ogni round reinvia l'intero transcript
/// in `input`, stesso approccio stateless già in uso per multi-turno su
/// [ClaudeAssistenteClient]. API key e modello letti a runtime da
/// [SettingsRepository].
class OpenAiAssistenteClient implements AssistenteClient {
  OpenAiAssistenteClient({
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
      AiProvider.openai,
    );
    if (apiKey == null || apiKey.isEmpty) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Nessuna API key configurata per OpenAI (ruolo Testuale) nelle '
        'Impostazioni.',
      );
    }
    final modello =
        settingsRepository.modello(
          RuoloProviderAi.testuale,
          AiProvider.openai,
        ) ??
        AiProvider.openai.modelloDefault(RuoloProviderAi.testuale);
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

    var input = <Map<String, Object?>>[
      for (final turno in storico)
        {
          'role': turno.ruolo == RuoloMessaggio.utente ? 'user' : 'assistant',
          'content': [
            {
              // La Responses API richiede 'output_text' per i turni
              // 'assistant' e 'input_text' per i turni 'user' — un turno
              // assistente rinviato con 'input_text' è rifiutato con 400
              // invalid_value.
              'type': turno.ruolo == RuoloMessaggio.utente
                  ? 'input_text'
                  : 'output_text',
              'text': turno.testo,
            },
          ],
        },
    ];

    for (var round = 0; round <= assistenteMaxRoundTool; round++) {
      final body = await _postResponses(apiKey, modello, input);
      final output = (body['output'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final functionCalls = output
          .where((o) => o['type'] == 'function_call')
          .toList();
      if (functionCalls.isEmpty) {
        final messaggio = output.firstWhere(
          (o) => o['type'] == 'message',
          orElse: () => const <String, dynamic>{},
        );
        final content = (messaggio['content'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>();
        final blocco = content?.firstWhere(
          (c) => c['type'] == 'output_text',
          orElse: () => const <String, dynamic>{},
        );
        if (blocco == null || blocco.isEmpty) {
          throw AssistenteException(
            SottotipoSistema.erroreProvider,
            'Risposta OpenAI senza testo: $body',
          );
        }
        return blocco['text'] as String;
      }

      final functionCallOutputs = <Map<String, Object?>>[];
      for (final call in functionCalls) {
        final argomenti =
            jsonDecode(call['arguments'] as String) as Map<String, dynamic>;
        final esito = await eseguiTool(call['name'] as String, argomenti);
        functionCallOutputs.add({
          'type': 'function_call_output',
          'call_id': call['call_id'],
          'output': jsonEncode(esito),
        });
      }

      input = [...input, ...output, ...functionCallOutputs];
    }

    throw AssistenteException(
      SottotipoSistema.erroreProvider,
      'Superato il numero massimo di round di tool-calling '
      '($assistenteMaxRoundTool).',
    );
  }

  Future<Map<String, dynamic>> _postResponses(
    String apiKey,
    String modello,
    List<Map<String, Object?>> input,
  ) async {
    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(_apiUrl),
            headers: _headers(apiKey),
            body: jsonEncode({
              'model': modello,
              'instructions': assistentePromptSistema,
              'tools': [for (final tool in assistenteTools) _toolOpenAi(tool)],
              'input': input,
            }),
          )
          .timeout(assistenteTimeout);
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreRete,
        "Chiamata all'API OpenAI fallita: $e",
      );
    }

    final responseBody = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'OpenAI API ${response.statusCode}: $responseBody',
      );
    }
    try {
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'Risposta OpenAI inattesa: $e',
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
          .timeout(assistenteTimeout);
    } on Object catch (e) {
      throw AssistenteException(
        SottotipoSistema.erroreRete,
        "Chiamata all'API OpenAI fallita: $e",
      );
    }

    if (response.statusCode != 200) {
      throw AssistenteException(
        SottotipoSistema.erroreProvider,
        'OpenAI API ${response.statusCode}: ${utf8.decode(response.bodyBytes)}',
      );
    }
  }
}
