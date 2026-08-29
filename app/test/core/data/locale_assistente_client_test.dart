import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/locale_assistente_client.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.risposte);

  final List<({int statusCode, String corpo})> risposte;
  final List<http.BaseRequest> richiesteRicevute = [];
  var _indice = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    richiesteRicevute.add(request);
    final risposta = risposte[_indice];
    _indice++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(risposta.corpo)),
      risposta.statusCode,
    );
  }
}

Future<SettingsRepository> _settingsConfigurate() async {
  final settings = SettingsRepository.inMemoria();
  await settings.impostaUrlLocale(
    RuoloProviderAi.testuale,
    'http://localhost:11434',
  );
  await settings.impostaModello(
    RuoloProviderAi.testuale,
    AiProvider.locale,
    'llama3',
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

void main() {
  test('costruisce l\'endpoint chat/completions rispetto all\'URL configurato', () async {
    final http_ = _FakeHttpClient([
      (statusCode: 200, corpo: _rispostaTesto('Ne hai 3.')),
    ]);
    final client = LocaleAssistenteClient(
      settingsRepository: await _settingsConfigurate(),
      httpClient: http_,
    );

    final risposta = await client.chiedi(
      storico: [(ruolo: RuoloMessaggio.utente, testo: 'Quanti Batman ho?')],
      eseguiTool: (_, _) async => throw StateError('non deve essere chiamato'),
    );

    expect(risposta, 'Ne hai 3.');
    expect(
      http_.richiesteRicevute.single.url.toString(),
      'http://localhost:11434/chat/completions',
    );
  });

  test('senza URL configurato solleva AssistenteException senza chiamare la rete', () async {
    final http_ = _FakeHttpClient([
      (statusCode: 200, corpo: _rispostaTesto('mai raggiunto')),
    ]);
    final client = LocaleAssistenteClient(
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
  });

  test('senza modello configurato solleva AssistenteException senza chiamare la rete', () async {
    final settings = SettingsRepository.inMemoria();
    await settings.impostaUrlLocale(
      RuoloProviderAi.testuale,
      'http://localhost:11434',
    );
    final http_ = _FakeHttpClient([
      (statusCode: 200, corpo: _rispostaTesto('mai raggiunto')),
    ]);
    final client = LocaleAssistenteClient(
      settingsRepository: settings,
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
  });

  group('verificaConnessione', () {
    test('con risposta non-200 solleva AssistenteException', () async {
      final client = LocaleAssistenteClient(
        settingsRepository: await _settingsConfigurate(),
        httpClient: _FakeHttpClient([
          (statusCode: 500, corpo: 'errore interno'),
        ]),
      );

      await expectLater(
        client.verificaConnessione,
        throwsA(isA<AssistenteException>()),
      );
    });
  });
}
