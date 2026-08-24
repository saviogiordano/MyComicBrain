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
import 'package:mycomicbrain/features/scheda/presentation/scheda_page.dart';

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
    tempBase = await Directory.systemTemp.createTemp('scheda_page_test_');
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

  Future<int> operaEdizione({
    String titolo = 'Batman',
    int? serieId,
    String? volume,
    String? description,
    String? printingType,
    String? classificazione,
  }) async {
    final operaId = await repository.aggiungiOpera(title: titolo);
    return repository.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      volume: volume,
      description: description,
      printingType: printingType,
      classificazione: classificazione,
    );
  }

  Future<void> pumpScheda(
    WidgetTester tester, {
    required int edizioneId,
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/scheda/$edizioneId',
      routes: [
        GoRoute(
          path: '/scheda/:id',
          builder: (context, state) =>
              SchedaPage(edizioneId: int.parse(state.pathParameters['id']!)),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicsRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'con 1 sola Copia, la riga è auto-espansa e mostra i suoi campi §8.2',
    (
      tester,
    ) async {
      final edizioneId = await operaEdizione(titolo: 'Batman');
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        readingStatus: StatoLettura.letto,
        condition: CondizioneCopia.veryFine,
        seller: 'Fumetteria Century',
      );

      await pumpScheda(tester, edizioneId: edizioneId);

      expect(find.text('Batman'), findsOneWidget);
      expect(find.text('COPIE (1)'), findsOneWidget);
      // Auto-espansa: i campi §8.2 sono già visibili senza dover toccare
      // l'accordion.
      expect(find.text('Fumetteria Century'), findsOneWidget);
    },
  );

  testWidgets(
    'con N Copie, ognuna compare come riga distinta dell\'accordion',
    (tester) async {
      final edizioneId = await operaEdizione(titolo: 'The Amazing Spider-Man');
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
        seller: 'Edicola di zona',
      );
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.prestata,
        seller: 'Convention Napoli Comicon',
      );
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.venduta,
      );

      await pumpScheda(tester, edizioneId: edizioneId);

      expect(find.text('COPIE (3)'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNWidgets(3));
    },
  );

  testWidgets(
    'mostra Tipo di stampa/Classificazione in griglia e il disclaimer AI sulla Descrizione',
    (tester) async {
      final edizioneId = await operaEdizione(
        titolo: 'Watchmen',
        printingType: 'Direct Edition',
        classificazione: 'Rated T+',
        description: 'Una storia di supereroi decostruita.',
      );
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      await pumpScheda(tester, edizioneId: edizioneId);

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('Tipo di stampa: Direct Edition'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('Classificazione: Rated T+'),
        ),
        findsOneWidget,
      );
      expect(
        find.text("Descrizione generata dall'AI: può contenere imprecisioni."),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    "un'Edizione senza Autori/Volume/Descrizione non fa comparire quelle sezioni e non va in errore",
    (tester) async {
      final edizioneId = await operaEdizione(titolo: 'Dylan Dog');
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      await pumpScheda(tester, edizioneId: edizioneId);

      expect(find.text('Dylan Dog'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Volume: —'),
        ),
        findsOneWidget,
      );
      // Nessun chip Autore, nessun testo di descrizione: solo il resto
      // della scheda deve essere renderizzato senza eccezioni (verificato
      // implicitamente dal pump senza errori).
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    "rimuovere l'ultima Copia elimina anche l'Edizione e torna indietro",
    (
      tester,
    ) async {
      final edizioneId = await operaEdizione(titolo: 'Saga');
      await repository.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => context.push('/scheda/$edizioneId'),
                  child: const Text('vai'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/scheda/:id',
            builder: (context, state) =>
                SchedaPage(edizioneId: int.parse(state.pathParameters['id']!)),
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

      await tester.tap(find.text('Rimuovi copia'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "È l'unica copia rimasta: eliminarla elimina anche l'edizione "
          '«Saga». Non è garantito poterlo annullare.',
        ),
        findsOneWidget,
        reason:
            'nessun dato personale su questa copia: avviso generico, non esplicito',
      );

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Conferma'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('vai'),
        findsOneWidget,
        reason: 'torna alla dashboard dopo la cancellazione',
      );
      final edizioneRiga = await (db.select(
        db.edizioni,
      )..where((e) => e.id.equals(edizioneId))).getSingleOrNull();
      expect(edizioneRiga, isNull);
    },
  );
}
