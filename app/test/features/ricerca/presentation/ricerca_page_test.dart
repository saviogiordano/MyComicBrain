import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/data/speech_to_text_service.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/features/ricerca/presentation/ricerca_page.dart';

typedef _EseguiTool =
    Future<Map<String, Object?>> Function(
      String nomeTool,
      Map<String, Object?> argomenti,
    );

/// [AssistenteClient] finto — stesso pattern di
/// `test/core/data/assistente_orchestrator_test.dart`: [onChiedi] decide la
/// risposta e può chiamare liberamente [_EseguiTool] per esercitare la
/// schermata contro dati reali del repository in memoria.
class _FakeAssistenteClient implements AssistenteClient {
  _FakeAssistenteClient(this.onChiedi);

  final Future<String> Function(
    List<TurnoConversazione> storico,
    _EseguiTool eseguiTool,
  )
  onChiedi;

  @override
  Future<String> chiedi({
    required List<TurnoConversazione> storico,
    required _EseguiTool eseguiTool,
  }) => onChiedi(storico, eseguiTool);

  @override
  Future<void> verificaConnessione() async {}
}

/// [SpeechToTextService] finto — [RisultatoAscolto] fisso al tocco del
/// microfono, senza toccare alcun plugin nativo (§10, #138).
class _FakeSpeechToTextService implements SpeechToTextService {
  _FakeSpeechToTextService(this.risultato);

  final RisultatoAscolto risultato;

  @override
  Future<RisultatoAscolto> ascolta({
    required ValueChanged<String> onParziale,
  }) async => risultato;

  @override
  Future<void> annulla() async {}

  @override
  bool get ascoltando => false;
}

/// Schermo Cerca (§10, chat dell'Assistente, variante A deciso su #125) —
/// verificato con dati reali su un repository in memoria, stesso pattern di
/// `serie_page_test.dart`. Le chiamate al Provider AI Testuale sono finte
/// (`_FakeAssistenteClient`): questo test copre solo la presentazione dello
/// stato già persistito, non i client reali (già coperti da
/// `assistente_orchestrator_test.dart` e dai test per-brand).
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
  });

  tearDown(() => db.close());

  Future<void> configuraProviderTestuale() async {
    await settingsRepository.impostaProviderAi(
      RuoloProviderAi.testuale,
      AiProvider.claude,
    );
    await settingsRepository.impostaApiKeyAi(
      RuoloProviderAi.testuale,
      AiProvider.claude,
      'chiave-test',
    );
  }

  Future<void> pumpCerca(
    WidgetTester tester, {
    AssistenteClient? client,
    SpeechToTextService? speechToTextService,
  }) async {
    final router = GoRouter(
      initialLocation: '/ricerca',
      routes: [
        GoRoute(
          path: '/ricerca',
          builder: (context, state) => const RicercaPage(),
        ),
        GoRoute(
          path: '/impostazioni',
          builder: (context, state) =>
              const Scaffold(body: Text('Impostazioni')),
        ),
        GoRoute(
          path: '/scheda/:id',
          builder: (context, state) => Scaffold(
            body: Text('Scheda ${state.pathParameters['id']}'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicsRepositoryProvider.overrideWithValue(repository),
          settingsRepositoryProvider.overrideWithValue(settingsRepository),
          if (client != null)
            assistenteClientProvider.overrideWithValue(client),
          if (speechToTextService != null)
            speechToTextServiceProvider.overrideWithValue(
              speechToTextService,
            ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('non configurato: banner bloccante e CTA verso Impostazioni', (
    tester,
  ) async {
    await pumpCerca(tester);

    expect(
      find.text("Configura il Provider AI Testuale per usare l'Assistente."),
      findsOneWidget,
    );
    expect(find.text('Configura il Provider per continuare'), findsOneWidget);

    await tester.tap(find.text('Vai a Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text('Impostazioni'), findsOneWidget);
  });

  testWidgets('configurato, nessun messaggio: stato vuoto con i 5 esempi', (
    tester,
  ) async {
    await configuraProviderTestuale();
    await pumpCerca(tester);

    expect(
      find.text('Chiedi qualcosa sulla tua collezione, a voce o scrivendo.'),
      findsOneWidget,
    );
    expect(find.text('Trova i duplicati.'), findsOneWidget);
    expect(
      find.text("Configura il Provider AI Testuale per usare l'Assistente."),
      findsNothing,
    );
  });

  testWidgets(
    'tap su una chip invia il messaggio e mostra la risposta con le Edizioni',
    (tester) async {
      await configuraProviderTestuale();
      final operaId = await repository.aggiungiOpera(title: 'Dylan Dog');
      final edizioneId = await repository.aggiungiEdizione(
        operaId: operaId,
        issueNumber: 1,
      );
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      await pumpCerca(
        tester,
        client: _FakeAssistenteClient((storico, eseguiTool) async {
          await eseguiTool('cercaEdizioni', const {});
          return 'Ecco le edizioni trovate.';
        }),
      );

      await tester.tap(find.text('Trova i duplicati.'));
      await tester.pumpAndSettle();

      expect(find.text('Trova i duplicati.'), findsOneWidget);
      expect(find.text('Ecco le edizioni trovate.'), findsOneWidget);
      expect(find.textContaining('Dylan Dog'), findsWidgets);

      await tester.tap(find.textContaining('Dylan Dog').last);
      await tester.pumpAndSettle();
      expect(find.text('Scheda $edizioneId'), findsOneWidget);
    },
  );

  testWidgets(
    'errore del provider: Messaggio di sistema con CTA verso Impostazioni',
    (tester) async {
      await configuraProviderTestuale();
      await pumpCerca(
        tester,
        client: _FakeAssistenteClient(
          (storico, eseguiTool) => throw AssistenteException(
            SottotipoSistema.erroreProvider,
            'chiave non valida',
          ),
        ),
      );

      await tester.tap(find.text('Trova i duplicati.'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Il Provider AI Testuale non risponde correttamente. Verifica la '
          'configurazione in Impostazioni.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Vai a Impostazioni'));
      await tester.pumpAndSettle();
      expect(find.text('Impostazioni'), findsOneWidget);
    },
  );

  testWidgets(
    'stato vuoto: nessun pulsante "Svuota chat" da mostrare',
    (tester) async {
      await configuraProviderTestuale();
      await pumpCerca(tester);

      expect(find.byIcon(Icons.delete_outline), findsNothing);
    },
  );

  testWidgets(
    'Svuota chat: conferma cancella la Conversazione e torna allo stato '
    'vuoto',
    (tester) async {
      await configuraProviderTestuale();
      await pumpCerca(
        tester,
        client: _FakeAssistenteClient(
          (storico, eseguiTool) async => 'Risposta.',
        ),
      );

      await tester.tap(find.text('Trova i duplicati.'));
      await tester.pumpAndSettle();
      expect(find.text('Risposta.'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Svuotare la chat?'), findsOneWidget);

      await tester.tap(find.text('Svuota'));
      await tester.pumpAndSettle();

      expect(find.text('Risposta.'), findsNothing);
      expect(
        find.text('Chiedi qualcosa sulla tua collezione, a voce o scrivendo.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    },
  );

  testWidgets(
    'Svuota chat: annullare la conferma non cancella nulla',
    (tester) async {
      await configuraProviderTestuale();
      await pumpCerca(
        tester,
        client: _FakeAssistenteClient(
          (storico, eseguiTool) async => 'Risposta.',
        ),
      );

      await tester.tap(find.text('Trova i duplicati.'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();

      expect(find.text('Risposta.'), findsOneWidget);
    },
  );

  testWidgets('microfono: il transcript viene inviato come Messaggio utente', (
    tester,
  ) async {
    await configuraProviderTestuale();
    await pumpCerca(
      tester,
      client: _FakeAssistenteClient(
        (storico, eseguiTool) async => 'Risposta.',
      ),
      speechToTextService: _FakeSpeechToTextService((
        testo: 'Quanti fumetti Marvel ho?',
        fallbackRete: false,
      )),
    );

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();

    expect(find.text('Quanti fumetti Marvel ho?'), findsOneWidget);
    expect(find.text('Risposta.'), findsOneWidget);
    expect(
      find.textContaining('riconoscimento vocale in rete'),
      findsNothing,
    );
  });

  testWidgets(
    'microfono: fallback rete Android aggiunge il Messaggio di sistema '
    'prima del transcript',
    (tester) async {
      await configuraProviderTestuale();
      await pumpCerca(
        tester,
        client: _FakeAssistenteClient(
          (storico, eseguiTool) async => 'Risposta.',
        ),
        speechToTextService: _FakeSpeechToTextService((
          testo: 'Quanti fumetti Marvel ho?',
          fallbackRete: true,
        )),
      );

      await tester.tap(find.byIcon(Icons.mic_none));
      await tester.pumpAndSettle();

      final messaggi = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      final indiceFallback = messaggi.indexWhere(
        (t) => t.contains('riconoscimento vocale in rete'),
      );
      final indiceTranscript = messaggi.indexOf('Quanti fumetti Marvel ho?');
      expect(indiceFallback, greaterThanOrEqualTo(0));
      expect(indiceTranscript, greaterThan(indiceFallback));
    },
  );
}
