import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/features/identificazione/presentation/inserisci_manualmente_page.dart';

void main() {
  late AppDatabase db;
  late ComicsRepository repository;
  late Directory tempBase;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    // `coverImagePerScansione`/`risolviCoverImage` (nuovi su #63) chiamano
    // `CopertinaDownloader.baseDirectory` — il vero `path_provider` non è
    // mockato in questo ambiente di test (stesso principio di
    // `comics_repository_test.dart`), quindi va iniettata una directory
    // temporanea.
    tempBase = await Directory.systemTemp.createTemp(
      'inserisci_manualmente_page_test_',
    );
    repository = ComicsRepository(
      db,
      copertinaDownloader: CopertinaDownloader(
        baseDirectory: () async => tempBase,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await tempBase.delete(recursive: true);
  });

  /// Una Scansione con un'Analisi Copertina già `completata` ma senza campi
  /// estratti — la pipeline reale crea sempre questa riga prima che
  /// `InserisciManualmentePage` sia raggiungibile (§6.3): il provider di
  /// prefill (`analisiCopertinaProvider`) la presuppone esistente.
  Future<int> scansione() async {
    final scansioneId = await repository.aggiungiScansione(
      image: '/scansioni/1.jpg',
    );
    final analisiId = await repository.avviaAnalisiCopertina(
      scansioneId: scansioneId,
    );
    await repository.completaAnalisiCopertina(id: analisiId, rawResponse: '{}');
    return scansioneId;
  }

  Future<void> pumpInserisciManualmente(
    WidgetTester tester, {
    required int scansioneId,
  }) async {
    // Il form ha molti più campi da #63 in poi (precompilati dall'AI):
    // non entrano più tutti nella viewport di test di default, e una
    // `ListView` non costruisce gli elementi fuori viewport (a differenza
    // di `find.byType`, che vede solo ciò che è montato). Una superficie
    // alta quanto basta evita di dover scrollare in ogni test per
    // raggiungere "Salva" o i campi in fondo.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      // `InserisciManualmentePage._salva()` fa `context.go('/dashboard')`
      // (deciso dopo un bug osservato — vedi il test dedicato sotto):
      // questa route deve esistere anche nel router minimo di test, o
      // `go` lancerebbe un'eccezione di route non trovata.
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push(
                  '/scansione/inserisci-manualmente',
                  extra: scansioneId,
                ),
                child: const Text('vai'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/scansione/inserisci-manualmente',
          builder: (context, state) =>
              InserisciManualmentePage(scansioneId: state.extra! as int),
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
    await tester.pumpAndSettle();
  }

  testWidgets('"Salva" è disabilitato finché il Titolo è vuoto', (
    tester,
  ) async {
    final scansioneId = await scansione();
    await pumpInserisciManualmente(tester, scansioneId: scansioneId);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'es. Batman'), 'Saga');
    await tester.pump();

    final buttonAbilitato = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(buttonAbilitato.onPressed, isNotNull);
  });

  testWidgets(
    'compilando solo il Titolo crea Opera + Edizione + Copia, nessuna Serie',
    (tester) async {
      final scansioneId = await scansione();
      await pumpInserisciManualmente(tester, scansioneId: scansioneId);

      await tester.enterText(
        find.widgetWithText(TextField, 'es. Batman'),
        'Saga sconosciuta',
      );
      await tester.pump();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(
        find.text('vai'),
        findsOneWidget,
        reason: 'torna alla dashboard',
      );

      final opere = await db.select(db.opere).get();
      expect(opere, hasLength(1));
      expect(opere.single.title, 'Saga sconosciuta');

      final serie = await db.select(db.serieTable).get();
      expect(serie, isEmpty);

      final edizioni = await db.select(db.edizioni).get();
      expect(edizioni, hasLength(1));
      expect(edizioni.single.operaId, opere.single.id);
      expect(edizioni.single.serieId, isNull);
      expect(edizioni.single.publisher, isNull);
      expect(edizioni.single.issueNumber, isNull);
      expect(edizioni.single.issueNumberLabel, isNull);

      final copie = await db.select(db.copie).get();
      expect(copie, hasLength(1));
      expect(copie.single.edizioneId, edizioni.single.id);
      expect(copie.single.status, StatoCopia.posseduta);
      expect(copie.single.scansioneId, scansioneId);
    },
  );

  testWidgets('il toggle Serie rivela il campo e crea la Serie collegata', (
    tester,
  ) async {
    final scansioneId = await scansione();
    await pumpInserisciManualmente(tester, scansioneId: scansioneId);

    expect(find.widgetWithText(TextField, 'es. Marvel Mega'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'es. Marvel Mega'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'es. Batman'),
      'Batman',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'es. Marvel Mega'),
      'Batman (2016)',
    );
    await tester.pump();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final serie = await db.select(db.serieTable).get();
    expect(serie, hasLength(1));
    expect(serie.single.name, 'Batman (2016)');

    final edizioni = await db.select(db.edizioni).get();
    expect(edizioni.single.serieId, serie.single.id);
  });

  testWidgets(
    'un Numero puramente numerico popola issueNumber e issueNumberLabel',
    (tester) async {
      final scansioneId = await scansione();
      await pumpInserisciManualmente(tester, scansioneId: scansioneId);

      await tester.enterText(
        find.widgetWithText(TextField, 'es. Batman'),
        'Dylan Dog',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'es. 42 oppure 42 Variant'),
        '42',
      );
      await tester.pump();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      final edizioni = await db.select(db.edizioni).get();
      expect(edizioni.single.issueNumber, 42);
      expect(edizioni.single.issueNumberLabel, '42');
    },
  );

  testWidgets(
    'un Numero non numerico (es. "42 Variant") popola solo issueNumberLabel',
    (tester) async {
      final scansioneId = await scansione();
      await pumpInserisciManualmente(tester, scansioneId: scansioneId);

      await tester.enterText(
        find.widgetWithText(TextField, 'es. Batman'),
        'Dylan Dog',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'es. 42 oppure 42 Variant'),
        '42 Variant',
      );
      await tester.pump();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      final edizioni = await db.select(db.edizioni).get();
      expect(edizioni.single.issueNumber, isNull);
      expect(edizioni.single.issueNumberLabel, '42 Variant');
    },
  );

  testWidgets(
    "il form arriva precompilato con l'Analisi Copertina AI (#63)",
    (tester) async {
      final scansioneId = await repository.aggiungiScansione(
        image: '/scansioni/1.jpg',
      );
      final analisiId = await repository.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await repository.completaAnalisiCopertina(
        id: analisiId,
        rawResponse: '{}',
        title: 'X-Men Forever – Parte 2',
        issueNumberLabel: '67',
        publisher: 'Marvel Italia / Panini Comics',
        seriesName: 'Marvel Mega',
        barcode: '977112421890900067',
        price: '€ 5,30',
        releaseDate: 'dicembre 2010',
        pageCount: 112,
        language: 'italiano',
        color: 'a colori',
        issn: '9771124218909',
        printingType: 'Direct Edition',
        classificazione: 'Rated T+',
        description: 'Una storia di supereroi.',
      );

      await pumpInserisciManualmente(tester, scansioneId: scansioneId);

      String testoDi(Key key) =>
          tester.widget<TextField>(find.byKey(key)).controller!.text;

      expect(testoDi(const Key('campo-titolo')), 'X-Men Forever – Parte 2');
      expect(testoDi(const Key('campo-collana')), 'Marvel Mega');
      expect(
        testoDi(const Key('campo-editore')),
        'Marvel Italia / Panini Comics',
      );
      expect(testoDi(const Key('campo-numero')), '67');
      expect(testoDi(const Key('campo-data-pubblicazione')), 'dicembre 2010');
      expect(testoDi(const Key('campo-prezzo-copertina')), '€ 5,30');
      expect(testoDi(const Key('campo-pagine')), '112');
      expect(testoDi(const Key('campo-lingua')), 'italiano');
      expect(testoDi(const Key('campo-colore')), 'a colori');
      expect(testoDi(const Key('campo-ean')), '977112421890900067');
      expect(testoDi(const Key('campo-tipo-stampa')), 'Direct Edition');
      expect(testoDi(const Key('campo-classificazione')), 'Rated T+');
      expect(
        testoDi(const Key('campo-descrizione')),
        'Una storia di supereroi.',
      );

      // Il toggle "fa parte di una collana" si attiva da solo perché l'AI
      // ha riconosciuto una collana — l'utente non deve riattivarlo a mano.
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        isTrue,
      );

      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      final edizioni = await db.select(db.edizioni).get();
      expect(edizioni.single.releaseDate, 'dicembre 2010');
      expect(edizioni.single.coverPrice, '€ 5,30');
      expect(edizioni.single.pageCount, 112);
      expect(edizioni.single.language, 'italiano');
      expect(edizioni.single.color, 'a colori');
      expect(edizioni.single.ean, '977112421890900067');
      expect(edizioni.single.printingType, 'Direct Edition');
      expect(edizioni.single.classificazione, 'Rated T+');
      expect(edizioni.single.description, 'Una storia di supereroi.');

      final serie = await db.select(db.serieTable).get();
      expect(serie.single.name, 'Marvel Mega');
      // Il campo ISSN è stato tolto dal form (ridondante con EAN/ISBN): non
      // viene più raccolto né salvato su Serie.
      expect(serie.single.issn, isNull);
    },
  );

  testWidgets(
    'dopo "Salva" torna alla dashboard invece che a "Possibile '
    'corrispondenza" — bug osservato: si poteva confermare per sbaglio '
    'anche il Candidato preselezionato lì sotto, creando 2 Copie per la '
    'stessa Scansione',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final scansioneId = await scansione();

      // Stub di "Possibile corrispondenza" (`ConfermaCandidatoPage`): un
      // bottone "Conferma" che, se ancora raggiungibile dopo il salvataggio
      // manuale, materializzerebbe esattamente il bug — una seconda Copia
      // per la stessa Scansione.
      var confermeCandidato = 0;
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Dashboard'))),
          ),
          GoRoute(
            path: '/scansione/conferma-candidato',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    confermeCandidato++;
                    context.push(
                      '/scansione/inserisci-manualmente',
                      extra: scansioneId,
                    );
                  },
                  child: const Text('Conferma'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/scansione/inserisci-manualmente',
            builder: (context, state) =>
                InserisciManualmentePage(scansioneId: state.extra! as int),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [comicsRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      router.go('/scansione/conferma-candidato');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conferma'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('campo-titolo')),
        'Saga sconosciuta',
      );
      await tester.pump();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(
        find.text('Conferma'),
        findsNothing,
        reason:
            '"Possibile corrispondenza" non deve più essere raggiungibile — '
            'altrimenti il suo Candidato preselezionato resta confermabile',
      );
      expect(
        confermeCandidato,
        1,
        reason: "mai più chiamato di quanto l'utente abbia effettivamente premuto",
      );

      final copie = await db.select(db.copie).get();
      expect(
        copie,
        hasLength(1),
        reason: 'una sola Copia per la Scansione, non due',
      );
    },
  );
}
