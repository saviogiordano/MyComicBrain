import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/features/dashboard/presentation/dashboard_page.dart';

void main() {
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    repo = ComicsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> pumpDashboard(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.dark, home: const DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'collezione a zero collassa a intestazione + CTA ingrandita, niente griglia (regola #8)',
    (tester) async {
      await pumpDashboard(tester);

      expect(find.text('È vuota — comincia dalla prima copertina'), findsOneWidget);
      expect(find.text('Scansiona la prima cover'), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(KpiCard), findsNothing);
    },
  );

  testWidgets(
    'collezione popolata mostra il totale e la griglia KPI sempre a 6 celle',
    (tester) async {
      final operaId = await repo.aggiungiOpera(title: 'Il Corvo');
      final serieId = await repo.aggiungiSerie(name: 'Il Corvo', totalIssues: 2);
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId, serieId: serieId, issueNumber: 1);
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta, purchasePrice: 12.5);

      await pumpDashboard(tester);

      expect(find.text('1'), findsWidgets);
      expect(find.text('fumetti'), findsOneWidget);
      expect(find.text('Scansiona una cover'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(KpiCard), findsNWidgets(6));
      // Duplicati e serie complete sono a zero in questo fixture: "—" muto,
      // non "0" (regola #8 — vale anche per celle non-di-allerta).
      expect(find.text('—'), findsNWidgets(2));
    },
  );
}
