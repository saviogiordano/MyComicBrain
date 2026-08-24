import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
import 'package:mycomicbrain/features/identificazione/presentation/conferma_candidato_page.dart';

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
    repository = ComicsRepository(db);
  });

  tearDown(() => db.close());

  Future<int> scansione() =>
      repository.aggiungiScansione(image: '/scansioni/1.jpg');

  Future<GoRouter> pumpConfermaCandidato(
    WidgetTester tester, {
    required int scansioneId,
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
              ConfermaCandidatoPage(scansioneId: state.extra! as int),
        ),
        GoRoute(
          path: '/scansione/inserisci-manualmente',
          builder: (context, state) =>
              Scaffold(body: Text('inserisci manualmente #${state.extra}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicsRepositoryProvider.overrideWithValue(repository)],
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
}
