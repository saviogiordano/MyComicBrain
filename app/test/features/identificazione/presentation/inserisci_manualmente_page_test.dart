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
import 'package:mycomicbrain/features/identificazione/presentation/inserisci_manualmente_page.dart';

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

  Future<void> pumpInserisciManualmente(
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
        reason: 'torna alla schermata precedente',
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

    expect(find.widgetWithText(TextField, 'es. Batman (2016)'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'es. Batman (2016)'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'es. Batman'),
      'Batman',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'es. Batman (2016)'),
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
}
