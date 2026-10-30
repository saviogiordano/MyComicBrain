import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/preferences.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
import 'package:mycomicbrain/features/identificazione/presentation/conferma_candidato_page.dart';

import '../../../core/auth/fake_auth_gateway.dart';

void main() {
  late AppDatabase db;
  late ComicsRepository repository;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repository = DriftComicsRepository(db);
  });

  tearDown(() => db.close());

  Future<String> scansione() =>
      repository.aggiungiScansione(image: '/scansioni/1.jpg');

  Future<GoRouter> pumpConfermaCandidato(
    WidgetTester tester, {
    required String scansioneId,
    List<Override> overrides = const [],
    Preferences? preferenze,
  }) async {
    final router = GoRouter(
      initialLocation: '/base',
      routes: [
        GoRoute(
          path: '/base',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push(
                  '/scansione/conferma-candidato',
                  extra: scansioneId,
                ),
                child: const Text('vai'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/scansione/conferma-candidato',
          builder: (context, state) =>
              ConfermaCandidatoPage(scansioneId: state.extra! as String),
        ),
        GoRoute(
          path: '/scansione/inserisci-manualmente',
          builder: (context, state) =>
              Scaffold(body: Text('inserisci manualmente #${state.extra}')),
        ),
        GoRoute(
          path: '/impostazioni',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Impostazioni'))),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicsRepositoryProvider.overrideWithValue(repository),
          accountPreferencesProvider.overrideWithValue(
            preferenze ?? PreferencesInMemoria(),
          ),
          ...overrides,
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.tap(find.text('vai'));
    // Niente `pumpAndSettle`: lo stato di caricamento è un
    // `CircularProgressIndicator` la cui animazione indeterminata non si
    // ferma mai, quindi va atteso con `pump` mirati invece.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return router;
  }

  testWidgets("mostra uno spinner finché l'Identificazione non è completata", (
    tester,
  ) async {
    final scansioneId = await scansione();
    await repository.avviaIdentificazione(scansioneId: scansioneId);

    await pumpConfermaCandidato(tester, scansioneId: scansioneId);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets(
    "un errore nel leggere l'Identificazione mostra l'errore, non uno "
    'spinner infinito (bug osservato su Supabase)',
    (tester) async {
      final scansioneId = await scansione();

      await pumpConfermaCandidato(
        tester,
        scansioneId: scansioneId,
        overrides: [
          identificazioneProvider(
            scansioneId,
          ).overrideWith((ref) => Stream.error(StateError('rete assente'))),
        ],
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Identificazione non riuscita'), findsOneWidget);
      expect(find.textContaining('rete assente'), findsOneWidget);
      expect(find.text('Inserisci manualmente'), findsOneWidget);
    },
  );

  testWidgets(
    'mostra i Candidati ordinati per confidenza, il migliore preselezionato',
    (tester) async {
      final scansioneId = await scansione();
      final identificazioneId = await repository.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repository.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 54,
        seriesName: 'Batman',
        issueNumberLabel: '41',
        publisher: 'DC Comics',
      );
      final operaId = await repository.aggiungiOpera(title: 'Batman');
      final edizioneId = await repository.aggiungiEdizione(
        operaId: operaId,
        issueNumberLabel: '42',
      );
      await repository.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.interno,
        punteggio: 96,
        edizioneId: edizioneId,
        title: 'Batman',
        issueNumberLabel: '42',
        publisher: 'DC Comics',
      );
      await repository.completaIdentificazione(id: identificazioneId);

      await pumpConfermaCandidato(tester, scansioneId: scansioneId);

      // `SectionHeader` maiuscolizza sempre `label`.
      expect(find.text('2 CANDIDATI, PER CONFIDENZA'), findsOneWidget);
      expect(find.text('96%'), findsOneWidget);
      expect(find.text('54%'), findsOneWidget);
      expect(find.text('Già in collezione'), findsOneWidget);
      expect(find.text('Nuovo · ComicVine'), findsOneWidget);
      // Il migliore (96%) è preselezionato: la sua icona è "checked".
      final icone = tester.widgetList<Icon>(
        find.byIcon(Icons.radio_button_checked),
      );
      expect(icone, hasLength(1));
    },
  );

  testWidgets(
    "l'icona info apre un popup con i dettagli del Candidato, senza "
    'cambiare la selezione',
    (tester) async {
      final scansioneId = await scansione();
      final identificazioneId = await repository.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repository.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 78,
        title: 'Amazing Spider-Man',
        seriesName: 'The Amazing Spider-Man',
        issueNumberLabel: '700',
        publisher: 'Marvel',
        year: 2013,
      );
      await repository.completaIdentificazione(id: identificazioneId);

      await pumpConfermaCandidato(tester, scansioneId: scansioneId);

      expect(find.byType(Dialog), findsNothing);
      // Lascia esaurire la transizione di push della route (~300ms): senza
      // questo pump aggiuntivo la riga è ancora a metà dello slide-in e
      // l'icona risulta fuori dal viewport per il tap, pur essendo
      // semanticamente presente nell'albero.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Amazing Spider-Man'), findsWidgets);
      expect(find.text('700'), findsOneWidget);
      expect(find.text('Marvel'), findsOneWidget);
      expect(find.text('2013'), findsOneWidget);
      expect(find.text('78%'), findsWidgets);

      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      // La selezione non è cambiata: l'unico candidato resta preselezionato.
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    },
  );

  testWidgets(
    '"Conferma" collega la Copia al candidato selezionato e torna indietro',
    (tester) async {
      final scansioneId = await scansione();
      final identificazioneId = await repository.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      final operaId = await repository.aggiungiOpera(title: 'Batman');
      final edizioneId = await repository.aggiungiEdizione(
        operaId: operaId,
        issueNumberLabel: '42',
      );
      await repository.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.interno,
        punteggio: 96,
        edizioneId: edizioneId,
        title: 'Batman',
      );
      await repository.completaIdentificazione(id: identificazioneId);

      await pumpConfermaCandidato(tester, scansioneId: scansioneId);
      await tester.tap(find.text('Conferma'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('vai'),
        findsOneWidget,
        reason: 'torna alla schermata precedente',
      );
      final copie = await db.select(db.copie).get();
      expect(copie, hasLength(1));
      expect(copie.single.edizioneId, edizioneId);
      expect(copie.single.scansioneId, scansioneId);
    },
  );

  testWidgets('stato vuoto per zero Candidati, con "Inserisci manualmente"', (
    tester,
  ) async {
    final scansioneId = await scansione();
    final identificazioneId = await repository.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repository.completaIdentificazione(id: identificazioneId);

    await pumpConfermaCandidato(tester, scansioneId: scansioneId);

    expect(find.text('Nessuna corrispondenza trovata'), findsOneWidget);
    expect(find.text('Inserisci manualmente'), findsOneWidget);

    await tester.tap(find.text('Inserisci manualmente'));
    await tester.pumpAndSettle();

    expect(
      find.text('inserisci manualmente #$scansioneId'),
      findsOneWidget,
      reason: 'naviga a /scansione/inserisci-manualmente con lo scansioneId',
    );
  });

  testWidgets("mostra lo stato di errore quando l'Identificazione è fallita", (
    tester,
  ) async {
    final scansioneId = await scansione();
    final identificazioneId = await repository.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repository.fallisciIdentificazione(
      id: identificazioneId,
      errorMessage: 'ComicVine offline',
    );

    await pumpConfermaCandidato(tester, scansioneId: scansioneId);

    expect(find.text('Identificazione non riuscita'), findsOneWidget);
    expect(find.text('ComicVine offline'), findsOneWidget);
    expect(find.text('Inserisci manualmente'), findsOneWidget);
  });

  testWidgets(
    'con ComicVine non configurato (#108) mostra un link diretto alle Impostazioni',
    (tester) async {
      final scansioneId = await scansione();
      final identificazioneId = await repository.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repository.fallisciIdentificazione(
        id: identificazioneId,
        errorMessage:
            'ComicVineException: Configurazione mancante: Nessuna API key ComicVine configurata nelle Impostazioni.',
      );

      final router = await pumpConfermaCandidato(
        tester,
        scansioneId: scansioneId,
      );

      expect(find.text('Provider fumetti non configurato'), findsOneWidget);
      expect(find.text('Apri Impostazioni'), findsOneWidget);
      expect(find.text('Inserisci manualmente'), findsOneWidget);

      await tester.tap(find.text('Apri Impostazioni'));
      await tester.pumpAndSettle();

      expect(find.text('Impostazioni'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/impostazioni',
      );
    },
  );

  group('Tutorial di inserimento, tappa "Possibile corrispondenza" (PRD #242)', () {
    const testoCandidato =
        'Ecco le corrispondenze, la più probabile in alto. Scegli e conferma';
    const testoManuale =
        'Nessuna è quella giusta? Inseriscilo a mano, la foto resta collegata';
    const testoSenzaCandidati =
        'Non ho trovato una corrispondenza: inseriscilo a mano, la foto resta '
        'collegata';

    PreferencesInMemoria inAttesa() =>
        PreferencesInMemoria()
          ..valori['tutorial.inserimento.fase'] = 'inAttesaPrimaScansione';

    Future<String> conUnCandidato() async {
      final scansioneId = await scansione();
      final identificazioneId = await repository.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repository.aggiungiCandidato(
        identificazioneId: identificazioneId,
        source: FonteCandidato.esterno,
        punteggio: 80,
        seriesName: 'Batman',
        issueNumberLabel: '41',
        publisher: 'DC Comics',
      );
      await repository.completaIdentificazione(id: identificazioneId);
      return scansioneId;
    }

    testWidgets('con Candidati: Candidato e poi "Inserisci manualmente", e '
        'il tutorial è visto', (tester) async {
      final preferenze = inAttesa();
      await pumpConfermaCandidato(
        tester,
        scansioneId: await conUnCandidato(),
        preferenze: preferenze,
      );
      await tester.pumpAndSettle();

      expect(find.text(testoCandidato), findsOneWidget);
      expect(preferenze.valori['tutorial.inserimento.fase'], 'visto');

      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();
      expect(find.text(testoManuale), findsOneWidget);

      await tester.tap(find.text('Ho capito'));
      await tester.pumpAndSettle();
      expect(find.text(testoManuale), findsNothing);
    });

    testWidgets('senza Candidati: solo "Inserisci manualmente"', (
      tester,
    ) async {
      final scansioneId = await scansione();
      final identificazioneId = await repository.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repository.completaIdentificazione(id: identificazioneId);
      final preferenze = inAttesa();

      await pumpConfermaCandidato(
        tester,
        scansioneId: scansioneId,
        preferenze: preferenze,
      );
      await tester.pumpAndSettle();

      expect(find.text(testoSenzaCandidati), findsOneWidget);
      expect(find.text(testoCandidato), findsNothing);
      expect(preferenze.valori['tutorial.inserimento.fase'], 'visto');
    });

    testWidgets('Identificazione fallita: solo "Inserisci manualmente"', (
      tester,
    ) async {
      final scansioneId = await scansione();
      final identificazioneId = await repository.avviaIdentificazione(
        scansioneId: scansioneId,
      );
      await repository.fallisciIdentificazione(
        id: identificazioneId,
        errorMessage: 'ComicVine irraggiungibile',
      );

      await pumpConfermaCandidato(
        tester,
        scansioneId: scansioneId,
        preferenze: inAttesa(),
      );
      await tester.pumpAndSettle();

      expect(find.text(testoSenzaCandidati), findsOneWidget);
    });

    testWidgets("aspetta la fine dell'Identificazione", (tester) async {
      final scansioneId = await scansione();
      await repository.avviaIdentificazione(scansioneId: scansioneId);
      final preferenze = inAttesa();

      await pumpConfermaCandidato(
        tester,
        scansioneId: scansioneId,
        preferenze: preferenze,
      );

      expect(find.text(testoSenzaCandidati), findsNothing);
      expect(
        preferenze.valori['tutorial.inserimento.fase'],
        'inAttesaPrimaScansione',
      );
    });

    testWidgets('a tutorial visto non compare', (tester) async {
      await pumpConfermaCandidato(tester, scansioneId: await conUnCandidato());
      await tester.pumpAndSettle();

      expect(find.text(testoCandidato), findsNothing);
    });
  });
}
