import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/features/serie/presentation/serie_dettaglio_page.dart';

/// Dettaglio `/serie/:id` (§11, deciso su #97) e il flusso di modifica
/// nome/numero totale/issn via bottom sheet (variante B, deciso su #99).
/// Verificato con dati reali su un repository in memoria — stessa
/// convenzione di `scheda_page_test.dart`.
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

  Future<int> edizioneConCopia({
    required String titolo,
    required int serieId,
    required int issueNumber,
    String? issueNumberLabel,
    String? coverImage,
    DateTime? createdAt,
  }) async {
    final operaId = await repository.aggiungiOpera(title: titolo);
    final edizioneId = await repository.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      issueNumber: issueNumber,
      issueNumberLabel: issueNumberLabel,
      coverImage: coverImage,
      createdAt: createdAt,
    );
    await repository.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
    );
    return edizioneId;
  }

  Future<void> pumpDettaglio(
    WidgetTester tester, {
    required int serieId,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/serie/$serieId',
      routes: [
        GoRoute(
          path: '/serie/:id',
          builder: (context, state) => SerieDettaglioPage(
            serieId: int.parse(state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/scheda/:id',
          builder: (context, state) =>
              Scaffold(body: Text('Scheda ${state.pathParameters['id']}')),
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
    'senza numero totale: chip dei posseduti e banner con CTA, niente griglia',
    (tester) async {
      final serieId = await repository.aggiungiSerie(name: 'Ombre di Marte');
      await edizioneConCopia(
        titolo: 'Ombre #1',
        serieId: serieId,
        issueNumber: 1,
      );
      await edizioneConCopia(
        titolo: 'Ombre #2',
        serieId: serieId,
        issueNumber: 2,
      );

      await pumpDettaglio(tester, serieId: serieId);

      expect(find.text('Numero totale non impostato'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('Imposta numero totale'), findsOneWidget);
      // "mancanti" mostra "—", non un conteggio: non valutabile senza totale.
      expect(find.text('—'), findsOneWidget);
    },
  );

  testWidgets('con numero totale: griglia con numeri posseduti/mancanti', (
    tester,
  ) async {
    final serieId = await repository.aggiungiSerie(
      name: 'Kaiju Bianco',
      totalIssues: 5,
    );
    for (final n in [1, 2, 3]) {
      await edizioneConCopia(
        titolo: 'Kaiju #$n',
        serieId: serieId,
        issueNumber: n,
      );
    }

    await pumpDettaglio(tester, serieId: serieId);

    expect(find.text('Ti mancano 2 numeri'), findsOneWidget);
    expect(find.text('#4, #5'), findsOneWidget);
    // Griglia 1..5: una cella per numero.
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Container),
      ),
      findsNWidgets(5),
    );
  });

  testWidgets('serie completa: badge "Serie completa"', (tester) async {
    final serieId = await repository.aggiungiSerie(
      name: 'Dylan Dog',
      totalIssues: 2,
    );
    for (final n in [1, 2]) {
      await edizioneConCopia(
        titolo: 'Dylan #$n',
        serieId: serieId,
        issueNumber: n,
      );
    }

    await pumpDettaglio(tester, serieId: serieId);

    expect(find.text('Serie completa'), findsOneWidget);
  });

  testWidgets(
    'tap su un numero con una sola Edizione naviga diretto alla Scheda',
    (tester) async {
      final serieId = await repository.aggiungiSerie(
        name: 'Kaiju Bianco',
        totalIssues: 3,
      );
      await edizioneConCopia(
        titolo: 'Kaiju #1',
        serieId: serieId,
        issueNumber: 1,
      );
      final edizione2 = await edizioneConCopia(
        titolo: 'Kaiju #2',
        serieId: serieId,
        issueNumber: 2,
      );

      await pumpDettaglio(tester, serieId: serieId);
      await tester.tap(
        find.descendant(of: find.byType(GridView), matching: find.text('2')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scheda $edizione2'), findsOneWidget);
    },
  );

  testWidgets(
    'tap su un numero con più Edizioni (variant) mostra un selettore prima di navigare',
    (tester) async {
      final serieId = await repository.aggiungiSerie(
        name: 'Kaiju Bianco',
        totalIssues: 4,
      );
      final normale = await edizioneConCopia(
        titolo: 'Kaiju #4',
        serieId: serieId,
        issueNumber: 4,
      );
      final variant = await edizioneConCopia(
        titolo: 'Kaiju #4 Variant',
        serieId: serieId,
        issueNumber: 4,
        issueNumberLabel: '4 Variant',
      );

      await pumpDettaglio(tester, serieId: serieId);
      await tester.tap(
        find.descendant(of: find.byType(GridView), matching: find.text('4')),
      );
      await tester.pumpAndSettle();

      // Nessuna navigazione automatica: il selettore mostra entrambe le
      // corrispondenze prima di scegliere.
      expect(find.text('Scheda $normale'), findsNothing);
      expect(find.text('Scheda $variant'), findsNothing);
      expect(find.text('#4'), findsOneWidget);
      expect(find.text('4 Variant'), findsOneWidget);

      await tester.tap(find.text('4 Variant'));
      await tester.pumpAndSettle();

      expect(find.text('Scheda $variant'), findsOneWidget);
    },
  );

  testWidgets(
    'CTA "Imposta numero totale" apre il bottom sheet (variante B, #99)',
    (tester) async {
      final serieId = await repository.aggiungiSerie(name: 'Ombre di Marte');
      await edizioneConCopia(
        titolo: 'Ombre #1',
        serieId: serieId,
        issueNumber: 1,
      );

      await pumpDettaglio(tester, serieId: serieId);
      await tester.tap(find.text('Imposta numero totale'));
      await tester.pumpAndSettle();

      expect(find.text('MODIFICA SERIE'), findsOneWidget);
      expect(find.text('Nome'), findsOneWidget);
      expect(find.text('Numero totale'), findsOneWidget);
      expect(find.text('ISSN'), findsOneWidget);
    },
  );

  testWidgets(
    'validazione: un totale sotto il numero posseduto più alto blocca il salvataggio',
    (tester) async {
      final serieId = await repository.aggiungiSerie(name: 'Ombre di Marte');
      for (final n in [1, 5, 8]) {
        await edizioneConCopia(
          titolo: 'Ombre #$n',
          serieId: serieId,
          issueNumber: n,
        );
      }

      await pumpDettaglio(tester, serieId: serieId);
      await tester.tap(find.text('Imposta numero totale'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'non impostato'),
        '5',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Non può essere inferiore a 8 (numero già posseduto).'),
        findsOneWidget,
      );
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Salva'),
      );
      expect(saveButton.onPressed, isNull);
    },
  );

  testWidgets(
    'salvataggio: aggiorna nome/totale/issn e la griglia riflette il nuovo totale',
    (tester) async {
      final serieId = await repository.aggiungiSerie(name: 'Ombre di Marte');
      for (final n in [1, 5, 8]) {
        await edizioneConCopia(
          titolo: 'Ombre #$n',
          serieId: serieId,
          issueNumber: n,
        );
      }

      await pumpDettaglio(tester, serieId: serieId);
      await tester.tap(find.text('Imposta numero totale'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'non impostato'),
        '10',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'es. 1122-3344'),
        '9988-7766',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
      await tester.pumpAndSettle();

      // Sheet chiuso, dettaglio aggiornato: griglia 1..10, ISSN mostrato,
      // 3 posseduti quindi 7 mancanti.
      expect(find.text('MODIFICA SERIE'), findsNothing);
      expect(find.text('ISSN 9988-7766'), findsOneWidget);
      expect(find.text('Ti mancano 7 numeri'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(GridView),
          matching: find.byType(Container),
        ),
        findsNWidgets(10),
      );
    },
  );

  testWidgets(
    "modifica: sezione cover senza override mostra Galleria e \"Da un'edizione\"",
    (tester) async {
      final serieId = await repository.aggiungiSerie(name: 'Ombre di Marte');
      await edizioneConCopia(
        titolo: 'Ombre #1',
        serieId: serieId,
        issueNumber: 1,
        coverImage: 'https://example.com/1.jpg',
      );

      await pumpDettaglio(tester, serieId: serieId);
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();

      expect(find.text('Galleria'), findsOneWidget);
      expect(find.text("Da un'edizione"), findsOneWidget);
      expect(find.text('Usa cover di default'), findsNothing);
    },
  );

  testWidgets(
    "modifica: scegliere \"da un'edizione\" imposta l'override e lo salva",
    (tester) async {
      final serieId = await repository.aggiungiSerie(name: 'Ombre di Marte');
      await edizioneConCopia(
        titolo: 'Ombre #1',
        serieId: serieId,
        issueNumber: 1,
        coverImage: 'https://example.com/1.jpg',
      );

      await pumpDettaglio(tester, serieId: serieId);
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Da un'edizione"));
      await tester.pumpAndSettle();

      // Un'unica Edizione nel selettore (nessuna griglia numeri sotto:
      // serie senza numero totale) — nessuna ambiguità sulla cover da toccare.
      await tester.tap(
        find.descendant(
          of: find.byType(GridView),
          matching: find.byType(ComicCoverImage),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Usa cover di default'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
      await tester.pumpAndSettle();

      final dettaglio = await repository.watchSerieDettaglio(serieId).first;
      expect(dettaglio!.coverImageOverride, 'https://example.com/1.jpg');
    },
  );

  testWidgets(
    'modifica: "Usa cover di default" azzera l\'override e lo salva',
    (tester) async {
      final serieId = await repository.aggiungiSerie(name: 'Ombre di Marte');
      await edizioneConCopia(
        titolo: 'Ombre #1',
        serieId: serieId,
        issueNumber: 1,
        coverImage: 'https://example.com/default.jpg',
      );
      await repository.aggiornaSerie(
        id: serieId,
        name: 'Ombre di Marte',
        coverImage: 'https://example.com/scelta.jpg',
      );

      await pumpDettaglio(tester, serieId: serieId);
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();

      expect(find.text('Usa cover di default'), findsOneWidget);
      await tester.tap(find.text('Usa cover di default'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
      await tester.pumpAndSettle();

      final dettaglio = await repository.watchSerieDettaglio(serieId).first;
      expect(dettaglio!.coverImageOverride, isNull);
      expect(dettaglio.coverImage, 'https://example.com/default.jpg');
    },
  );
}
