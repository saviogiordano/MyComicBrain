import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/openrouter_assistente_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.risposte);

  final List<({int statusCode, String corpo})> risposte;
  final List<Map<String, dynamic>> richiesteRicevute = [];
  var _indice = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = (request as http.Request).body;
    richiesteRicevute.add(jsonDecode(body) as Map<String, dynamic>);
    final risposta = risposte[_indice];
    _indice++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(risposta.corpo)),
      risposta.statusCode,
    );
  }
}

Future<SettingsRepository> _settingsConApiKey() async {
  final settings = SettingsRepository.inMemoria();
  await settings.impostaApiKeyAi(
    RuoloProviderAi.testuale,
    AiProvider.openRouter,
    'chiave-test',
  );
  return settings;
}

String _rispostaTesto(String testo) => jsonEncode({
  'choices': [
    {
      'message': {'role': 'assistant', 'content': testo},
    },
  ],
});

String _rispostaToolCall({
  required String id,
  required String nome,
  required Map<String, dynamic> argomenti,
}) => jsonEncode({
  'choices': [
    {
      'message': {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': id,
            'type': 'function',
            'function': {'name': nome, 'arguments': jsonEncode(argomenti)},
          },
        ],
      },
    },
  ],
});

void main() {
  test('una risposta senza tool_calls ritorna direttamente il testo', () async {
    final client = OpenRouterAssistenteClient(
      settingsRepository: await _settingsConApiKey(),
      httpClient: _FakeHttpClient([
        (statusCode: 200, corpo: _rispostaTesto('Ne hai 3.')),
      ]),
    );

    final risposta = await client.chiedi(
      storico: [(ruolo: RuoloMessaggio.utente, testo: 'Quanti Batman ho?')],
      eseguiTool: (_, _) async => throw StateError('non deve essere chiamato'),
    );

    expect(risposta, 'Ne hai 3.');
  });

  test('un tool_call esegue il tool e reinvia il messaggio role:tool', () async {
    final http_ = _FakeHttpClient([
      (
        statusCode: 200,
        corpo: _rispostaToolCall(
          id: 'call_1',
          nome: 'serieQuasiComplete',
          argomenti: {},
        ),
      ),
      (statusCode: 200, corpo: _rispostaTesto('Ecco le serie.')),
    ]);
    final client = OpenRouterAssistenteClient(
      settingsRepository: await _settingsConApiKey(),
      httpClient: http_,
    );

    var toolChiamato = false;
    final risposta = await client.chiedi(
      storico: [(ruolo: RuoloMessaggio.utente, testo: 'Serie quasi complete?')],
      eseguiTool: (nome, argomenti) async {
        toolChiamato = true;
        expect(nome, 'serieQuasiComplete');
        return {'serie': <dynamic>[]};
      },
    );

    expect(toolChiamato, isTrue);
    expect(risposta, 'Ecco le serie.');

    final secondaRichiesta = http_.richiesteRicevute[1];
    final messages = secondaRichiesta['messages'] as List<dynamic>;
    final ultimo = messages.last as Map<String, dynamic>;
    expect(ultimo['role'], 'tool');
    expect(ultimo['tool_call_id'], 'call_1');
    expect(jsonDecode(ultimo['content'] as String), {'serie': <dynamic>[]});
  });

  test(
    'un fallimento della chiamata HTTP solleva AssistenteException di tipo rete',
    () async {
      final client = OpenRouterAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _ThrowingHttpClient(),
      );

      await expectLater(
        () => client.chiedi(
          storico: [(ruolo: RuoloMessaggio.utente, testo: 'Ciao')],
          eseguiTool: (_, _) async => {},
        ),
        throwsA(
          isA<AssistenteException>().having(
            (e) => e.sottotipo,
            'sottotipo',
            SottotipoSistema.erroreRete,
          ),
        ),
      );
    },
  );

  test(
    'senza API key configurata solleva AssistenteException senza chiamare la rete',
    () async {
      final http_ = _FakeHttpClient([
        (statusCode: 200, corpo: _rispostaTesto('mai raggiunto')),
      ]);
      final client = OpenRouterAssistenteClient(
        settingsRepository: SettingsRepository.inMemoria(),
        httpClient: http_,
      );

      await expectLater(
        () => client.chiedi(
          storico: [(ruolo: RuoloMessaggio.utente, testo: 'Ciao')],
          eseguiTool: (_, _) async => {},
        ),
        throwsA(isA<AssistenteException>()),
      );
      expect(http_.richiesteRicevute, isEmpty);
    },
  );

  group('verificaConnessione', () {
    test('con risposta non-200 solleva AssistenteException', () async {
      final client = OpenRouterAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient([
          (statusCode: 401, corpo: '{"error": "invalid api key"}'),
        ]),
      );

      await expectLater(
        client.verificaConnessione,
        throwsA(isA<AssistenteException>()),
      );
    });
  });
}

class _ThrowingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw Exception('rete assente');
  }
}
