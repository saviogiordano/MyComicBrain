import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/claude_assistente_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';

/// `http.Client` finto che risponde in sequenza con i corpi/status passati,
/// una risposta per ogni POST ricevuto — stesso principio del client finto
/// dei test di `ClaudeCoverAnalysisClient`, esteso a più round.
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
    AiProvider.claude,
    'chiave-test',
  );
  return settings;
}

String _rispostaTesto(String testo) => jsonEncode({
  'content': [
    {'type': 'text', 'text': testo},
  ],
});

String _rispostaToolUse({
  required String id,
  required String nome,
  required Map<String, dynamic> input,
}) => jsonEncode({
  'content': [
    {'type': 'tool_use', 'id': id, 'name': nome, 'input': input},
  ],
});

void main() {
  test('una risposta senza tool_use ritorna direttamente il testo', () async {
    final http_ = _FakeHttpClient([
      (statusCode: 200, corpo: _rispostaTesto('Ne hai 3.')),
    ]);
    final client = ClaudeAssistenteClient(
      settingsRepository: await _settingsConApiKey(),
      httpClient: http_,
    );

    final risposta = await client.chiedi(
      storico: [(ruolo: RuoloMessaggio.utente, testo: 'Quanti Batman ho?')],
      eseguiTool: (_, _) async => throw StateError('non deve essere chiamato'),
    );

    expect(risposta, 'Ne hai 3.');
  });

  test(
    'un tool_use esegue il tool e reinvia il tool_result, poi ritorna il testo finale',
    () async {
      final http_ = _FakeHttpClient([
        (
          statusCode: 200,
          corpo: _rispostaToolUse(
            id: 'toolu_1',
            nome: 'conteggioPer',
            input: {'campo': 'editore'},
          ),
        ),
        (statusCode: 200, corpo: _rispostaTesto('Hai 3 albi Marvel.')),
      ]);
      final client = ClaudeAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: http_,
      );

      var toolChiamato = false;
      final risposta = await client.chiedi(
        storico: [(ruolo: RuoloMessaggio.utente, testo: 'Quanti per editore?')],
        eseguiTool: (nome, argomenti) async {
          toolChiamato = true;
          expect(nome, 'conteggioPer');
          expect(argomenti, {'campo': 'editore'});
          return {'Marvel': 3};
        },
      );

      expect(toolChiamato, isTrue);
      expect(risposta, 'Hai 3 albi Marvel.');

      final secondaRichiesta = http_.richiesteRicevute[1];
      final messages = secondaRichiesta['messages'] as List<dynamic>;
      expect(messages, hasLength(3));
      final ultimo = messages.last as Map<String, dynamic>;
      expect(ultimo['role'], 'user');
      final toolResult =
          (ultimo['content'] as List<dynamic>).single as Map<String, dynamic>;
      expect(toolResult['type'], 'tool_result');
      expect(toolResult['tool_use_id'], 'toolu_1');
      expect(jsonDecode(toolResult['content'] as String), {'Marvel': 3});
    },
  );

  test(
    'un fallimento della chiamata HTTP solleva AssistenteException di tipo rete',
    () async {
      final client = ClaudeAssistenteClient(
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
      final client = ClaudeAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient([
          (statusCode: 401, corpo: '{"error": "invalid api key"}'),
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
      final client = ClaudeAssistenteClient(
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

  test(
    'un loop di tool-calling che non converge solleva AssistenteException di tipo provider',
    () async {
      final risposte = List.generate(
        assistenteMaxRoundTool + 1,
        (_) => (
          statusCode: 200,
          corpo: _rispostaToolUse(
            id: 'toolu_loop',
            nome: 'serieQuasiComplete',
            input: <String, dynamic>{},
          ),
        ),
      );
      final client = ClaudeAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient(risposte),
      );

      await expectLater(
        () => client.chiedi(
          storico: [(ruolo: RuoloMessaggio.utente, testo: 'Ciao')],
          eseguiTool: (_, _) async => {'serie': <dynamic>[]},
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

  group('verificaConnessione', () {
    test('con risposta 200 non solleva nulla', () async {
      final client = ClaudeAssistenteClient(
        settingsRepository: await _settingsConApiKey(),
        httpClient: _FakeHttpClient([(statusCode: 200, corpo: '{}')]),
      );

      await client.verificaConnessione();
    });

    test('con risposta non-200 solleva AssistenteException', () async {
      final client = ClaudeAssistenteClient(
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
