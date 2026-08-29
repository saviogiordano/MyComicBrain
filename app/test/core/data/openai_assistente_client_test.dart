import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/openai_assistente_client.dart';
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
    AiProvider.openai,
    'chiave-test',
  );
  return settings;
}

String _rispostaTesto(String testo) => jsonEncode({
  'output': [
    {
      'type': 'message',
      'content': [
        {'type': 'output_text', 'text': testo},
      ],
    },
  ],
});

String _rispostaFunctionCall({
  required String callId,
  required String nome,
  required Map<String, dynamic> argomenti,
}) => jsonEncode({
  'output': [
    {
      'type': 'function_call',
      'call_id': callId,
      'name': nome,
      'arguments': jsonEncode(argomenti),
    },
  ],
});

void main() {
  test(
    'una risposta senza function_call ritorna direttamente il testo',
    () async {
      final client = OpenAiAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient([
          (statusCode: 200, corpo: _rispostaTesto('Ne hai 3.')),
        ]),
      );

      final risposta = await client.chiedi(
        storico: [(ruolo: RuoloMessaggio.utente, testo: 'Quanti Batman ho?')],
        eseguiTool: (_, _) async =>
            throw StateError('non deve essere chiamato'),
      );

      expect(risposta, 'Ne hai 3.');
    },
  );

  test(
    'una function_call esegue il tool e reinvia il function_call_output',
    () async {
      final http_ = _FakeHttpClient([
        (
          statusCode: 200,
          corpo: _rispostaFunctionCall(
            callId: 'call_1',
            nome: 'conteggioPer',
            argomenti: {'campo': 'anno'},
          ),
        ),
        (statusCode: 200, corpo: _rispostaTesto('Ecco il conteggio.')),
      ]);
      final client = OpenAiAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: http_,
      );

      var toolChiamato = false;
      final risposta = await client.chiedi(
        storico: [(ruolo: RuoloMessaggio.utente, testo: 'Per anno?')],
        eseguiTool: (nome, argomenti) async {
          toolChiamato = true;
          expect(nome, 'conteggioPer');
          expect(argomenti, {'campo': 'anno'});
          return {'2020': 2};
        },
      );

      expect(toolChiamato, isTrue);
      expect(risposta, 'Ecco il conteggio.');

      final secondaRichiesta = http_.richiesteRicevute[1];
      final input = secondaRichiesta['input'] as List<dynamic>;
      final output = input.last as Map<String, dynamic>;
      expect(output['type'], 'function_call_output');
      expect(output['call_id'], 'call_1');
      expect(jsonDecode(output['output'] as String), {'2020': 2});
    },
  );

  test(
    'un fallimento della chiamata HTTP solleva AssistenteException di tipo rete',
    () async {
      final client = OpenAiAssistenteClient(
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
    'una risposta HTTP non-200 solleva AssistenteException di tipo provider',
    () async {
      final client = OpenAiAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient([
          (statusCode: 500, corpo: 'errore interno'),
        ]),
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
            SottotipoSistema.erroreProvider,
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
      final client = OpenAiAssistenteClient(
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
    test('con risposta 200 non solleva nulla', () async {
      final client = OpenAiAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient([(statusCode: 200, corpo: '{}')]),
      );

      await client.verificaConnessione();
    });

    test('con risposta non-200 solleva AssistenteException', () async {
      final client = OpenAiAssistenteClient(
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
