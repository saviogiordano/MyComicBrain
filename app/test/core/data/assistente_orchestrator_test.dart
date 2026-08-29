import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/assistente_orchestrator.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';
import 'package:mycomicbrain/core/domain/copia.dart';

typedef _EseguiTool =
    Future<Map<String, Object?>> Function(
      String nomeTool,
      Map<String, Object?> argomenti,
    );

/// [AssistenteClient] finto: [onChiedi] decide la risposta e può chiamare
/// liberamente [_EseguiTool] per esercitare l'orchestratore contro
/// `ComicsRepository` senza passare da una vera rete/API.
class _FakeAssistenteClient implements AssistenteClient {
  _FakeAssistenteClient({required this.onChiedi, this.onVerificaConnessione});

  final Future<String> Function(
    List<TurnoConversazione> storico,
    _EseguiTool eseguiTool,
  )
  onChiedi;
  final Future<void> Function()? onVerificaConnessione;

  @override
  Future<String> chiedi({
    required List<TurnoConversazione> storico,
    required _EseguiTool eseguiTool,
  }) {
    return onChiedi(storico, eseguiTool);
  }

  @override
  Future<void> verificaConnessione() =>
      onVerificaConnessione?.call() ?? Future.value();
}

void main() {
  late AppDatabase db;
  late ComicsRepository repository;
  late SettingsRepository settingsRepository;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repository = ComicsRepository(db);
    settingsRepository = SettingsRepository.inMemoria();
    await settingsRepository.impostaProviderAi(
      RuoloProviderAi.testuale,
      AiProvider.claude,
    );
    await settingsRepository.impostaApiKeyAi(
      RuoloProviderAi.testuale,
      AiProvider.claude,
      'chiave-test',
    );
  });

  tearDown(() => db.close());

  AssistenteOrchestrator orchestratore(AssistenteClient client) {
    return AssistenteOrchestrator(
      repository: repository,
      settingsRepository: settingsRepository,
      client: client,
    );
  }

  group('configurato (#123)', () {
    test('true quando il ruolo Testuale ha una API key', () async {
      final orch = orchestratore(
        _FakeAssistenteClient(onChiedi: (_, _) async => 'mai chiamato'),
      );
      expect(await orch.configurato(), isTrue);
    });

    test('false senza alcun provider selezionato', () async {
      final settingsVuote = SettingsRepository.inMemoria();
      final orch = AssistenteOrchestrator(
        repository: repository,
        settingsRepository: settingsVuote,
        client: _FakeAssistenteClient(onChiedi: (_, _) async => 'x'),
      );
      expect(await orch.configurato(), isFalse);
    });
  });

  test(
    'inviaMessaggio solleva StateError e non persiste nulla se non configurato (#123)',
    () async {
      final settingsVuote = SettingsRepository.inMemoria();
      final orch = AssistenteOrchestrator(
        repository: repository,
        settingsRepository: settingsVuote,
        client: _FakeAssistenteClient(
          onChiedi: (_, _) async => throw StateError('non deve essere chiamato'),
        ),
      );

      await expectLater(
        () => orch.inviaMessaggio('Ciao'),
        throwsA(isA<StateError>()),
      );

      final conversazioni = await db.select(db.conversazioneTable).get();
      expect(conversazioni, isEmpty);
    },
  );

  test(
    'inviaMessaggio persiste il Messaggio utente e la risposta assistente',
    () async {
      final orch = orchestratore(
        _FakeAssistenteClient(
          onChiedi: (storico, eseguiTool) async {
            expect(storico, hasLength(1));
            expect(storico.single.ruolo, RuoloMessaggio.utente);
            expect(storico.single.testo, 'Quanti Batman ho?');
            return 'Ne hai 3.';
          },
        ),
      );

      await orch.inviaMessaggio('Quanti Batman ho?');

      final conversazioneId = await repository.getOrCreaConversazione();
      final messaggi = await repository.watchMessaggi(conversazioneId).first;
      expect(messaggi, hasLength(2));
      expect(messaggi[0].ruolo, RuoloMessaggio.utente);
      expect(messaggi[0].testo, 'Quanti Batman ho?');
      expect(messaggi[1].ruolo, RuoloMessaggio.assistente);
      expect(messaggi[1].testo, 'Ne hai 3.');
    },
  );

  test(
    'lo storico passato al client esclude i Messaggi di sistema',
    () async {
      final conversazioneId = await repository.getOrCreaConversazione();
      await repository.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.sistema,
        sottotipoSistema: SottotipoSistema.erroreRete,
        testo: 'Connessione assente. Riprova quando sei di nuovo online.',
      );
      await repository.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.utente,
        testo: 'Prima domanda',
      );
      await repository.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.assistente,
        testo: 'Prima risposta',
      );

      final orch = orchestratore(
        _FakeAssistenteClient(
          onChiedi: (storico, _) async {
            expect(storico, hasLength(3));
            expect(
              storico.map((t) => t.ruolo),
              everyElement(isNot(RuoloMessaggio.sistema)),
            );
            return 'Seconda risposta';
          },
        ),
      );

      await orch.inviaMessaggio('Seconda domanda');
    },
  );

  group('errori runtime (#124)', () {
    test(
      'errore di rete persiste un Messaggio di sistema col copy di rete',
      () async {
        final orch = orchestratore(
          _FakeAssistenteClient(
            onChiedi: (_, _) async => throw AssistenteException(
              SottotipoSistema.erroreRete,
              'dettaglio tecnico irrilevante per la UI',
            ),
          ),
        );

        await orch.inviaMessaggio('Ciao');

        final conversazioneId = await repository.getOrCreaConversazione();
        final messaggi = await repository.watchMessaggi(conversazioneId).first;
        final ultimo = messaggi.last;
        expect(ultimo.ruolo, RuoloMessaggio.sistema);
        expect(ultimo.sottotipoSistema, SottotipoSistema.erroreRete);
        expect(
          ultimo.testo,
          'Connessione assente. Riprova quando sei di nuovo online.',
        );
      },
    );

    test(
      'errore di provider persiste un Messaggio di sistema col copy di provider',
      () async {
        final orch = orchestratore(
          _FakeAssistenteClient(
            onChiedi: (_, _) async => throw AssistenteException(
              SottotipoSistema.erroreProvider,
              'API key non valida',
            ),
          ),
        );

        await orch.inviaMessaggio('Ciao');

        final conversazioneId = await repository.getOrCreaConversazione();
        final messaggi = await repository.watchMessaggi(conversazioneId).first;
        final ultimo = messaggi.last;
        expect(ultimo.ruolo, RuoloMessaggio.sistema);
        expect(ultimo.sottotipoSistema, SottotipoSistema.erroreProvider);
        expect(
          ultimo.testo,
          'Il Provider AI Testuale non risponde correttamente. Verifica la '
          'configurazione in Impostazioni.',
        );
      },
    );
  });

  group('tool cercaEdizioni', () {
    test('restituisce le Edizioni trovate e le cita nel blocco Edizioni', () async {
      final operaId = await repository.aggiungiOpera(
        title: 'The Amazing Spider-Man',
      );
      final edizioneId = await repository.aggiungiEdizione(
        operaId: operaId,
        publisher: 'Marvel',
        issueNumberLabel: '300',
      );
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final orch = orchestratore(
        _FakeAssistenteClient(
          onChiedi: (_, eseguiTool) async {
            final esito = await eseguiTool('cercaEdizioni', {
              'editore': 'Marvel',
            });
            expect(esito['totale'], 1);
            expect(esito['troncato'], false);
            final edizioni = esito['edizioni'] as List<dynamic>;
            expect(edizioni, hasLength(1));
            expect(
              (edizioni.single as Map)['titolo'],
              'The Amazing Spider-Man',
            );
            return 'Trovato un albo Marvel.';
          },
        ),
      );

      await orch.inviaMessaggio('Cosa ho della Marvel?');

      final conversazioneId = await repository.getOrCreaConversazione();
      final messaggi = await repository.watchMessaggi(conversazioneId).first;
      expect(messaggi.last.edizioni, hasLength(1));
      expect(messaggi.last.edizioni.single.edizioneId, edizioneId);
    });
  });

  group('tool numeriMancantiSerie', () {
    test('nessun match riporta trovata:false', () async {
      final orch = orchestratore(
        _FakeAssistenteClient(
          onChiedi: (_, eseguiTool) async {
            final esito = await eseguiTool('numeriMancantiSerie', {
              'nomeSerie': 'Serie inesistente',
            });
            expect(esito, {'trovata': false});
            return 'Non trovata.';
          },
        ),
      );

      await orch.inviaMessaggio('Numeri mancanti di Serie inesistente?');
    });

    test('più match riporta ambiguo:true coi candidati', () async {
      await repository.aggiungiSerie(name: 'Batman', totalIssues: 5);
      await repository.aggiungiSerie(name: 'Batman Beyond', totalIssues: 5);

      final orch = orchestratore(
        _FakeAssistenteClient(
          onChiedi: (_, eseguiTool) async {
            final esito = await eseguiTool('numeriMancantiSerie', {
              'nomeSerie': 'Batman',
            });
            expect(esito['ambiguo'], true);
            expect(esito['candidati'], containsAll(['Batman', 'Batman Beyond']));
            return 'Quale delle due intendi?';
          },
        ),
      );

      await orch.inviaMessaggio('Numeri mancanti di Batman?');
    });

    test('un solo match riporta i numeri mancanti', () async {
      final serieId = await repository.aggiungiSerie(
        name: 'Daredevil',
        totalIssues: 3,
      );
      final operaId = await repository.aggiungiOpera(title: 'Daredevil #1');
      final edizioneId = await repository.aggiungiEdizione(
        operaId: operaId,
        serieId: serieId,
        issueNumber: 1,
      );
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final orch = orchestratore(
        _FakeAssistenteClient(
          onChiedi: (_, eseguiTool) async {
            final esito = await eseguiTool('numeriMancantiSerie', {
              'nomeSerie': 'Daredevil',
            });
            expect(esito['trovata'], true);
            expect(esito['completa'], false);
            expect(esito['numeriMancanti'], [2, 3]);
            return 'Ti mancano il 2 e il 3.';
          },
        ),
      );

      await orch.inviaMessaggio('Numeri mancanti di Daredevil?');
    });
  });

  group('tool conteggioPer / serieQuasiComplete / trovaDuplicati', () {
    test('conteggioPer aggrega per editore', () async {
      final operaId = await repository.aggiungiOpera(title: 'Albo');
      final edizioneId = await repository.aggiungiEdizione(
        operaId: operaId,
        publisher: 'Marvel',
      );
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final orch = orchestratore(
        _FakeAssistenteClient(
          onChiedi: (_, eseguiTool) async {
            final esito = await eseguiTool('conteggioPer', {
              'campo': 'editore',
            });
            expect(esito, {'Marvel': 1});
            return 'Hai 1 albo Marvel.';
          },
        ),
      );

      await orch.inviaMessaggio('Quanti albi per editore?');
    });

    test('trovaDuplicati cita le Edizioni possedute più volte', () async {
      final operaId = await repository.aggiungiOpera(title: 'Doppione');
      final edizioneId = await repository.aggiungiEdizione(operaId: operaId);
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      final orch = orchestratore(
        _FakeAssistenteClient(
          onChiedi: (_, eseguiTool) async {
            final esito = await eseguiTool('trovaDuplicati', {});
            final duplicati = esito['duplicati'] as List<dynamic>;
            expect(duplicati, hasLength(1));
            return 'Hai un doppione.';
          },
        ),
      );

      await orch.inviaMessaggio('Ho dei doppioni?');

      final conversazioneId = await repository.getOrCreaConversazione();
      final messaggi = await repository.watchMessaggi(conversazioneId).first;
      expect(messaggi.last.edizioni.single.edizioneId, edizioneId);
    });

    test('serieQuasiComplete riporta le serie sopra soglia', () async {
      final serieId = await repository.aggiungiSerie(
        name: 'X-Men',
        totalIssues: 5,
      );
      for (final numero in [1, 2, 3, 4]) {
        final operaId = await repository.aggiungiOpera(title: 'X-Men #$numero');
        final edizioneId = await repository.aggiungiEdizione(
          operaId: operaId,
          serieId: serieId,
          issueNumber: numero,
        );
        await repository.aggiungiCopia(
          edizioneId: edizioneId,
          status: StatoCopia.posseduta,
        );
      }

      final orch = orchestratore(
        _FakeAssistenteClient(
          onChiedi: (_, eseguiTool) async {
            final esito = await eseguiTool('serieQuasiComplete', {});
            final serie = esito['serie'] as List<dynamic>;
            expect(serie, hasLength(1));
            expect((serie.single as Map)['nome'], 'X-Men');
            return 'X-Men è quasi completa.';
          },
        ),
      );

      await orch.inviaMessaggio('Quali serie sono quasi complete?');
    });
  });
}
