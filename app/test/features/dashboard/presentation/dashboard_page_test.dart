import 'dart:convert';
import 'dart:io';

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

  testWidgets(
    '"Serie incomplete" nascosta se non ci sono serie valutabili, "Aggiunti di recente" mostrata (regola #8)',
    (tester) async {
      // Copia posseduta senza serie: "Aggiunti di recente" ha materiale,
      // "Serie incomplete" no (nessuna serie con "numeri totali" noto).
      final operaId = await repo.aggiungiOpera(title: 'Il Corvo');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId, issueNumber: 1);
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

      await pumpDashboard(tester);

      expect(find.text('AGGIUNTI DI RECENTE'), findsOneWidget);
      expect(find.text('SERIE INCOMPLETE'), findsNothing);
    },
  );

  testWidgets(
    'carosello "Aggiunti di recente" mostra le copie possedute, più recenti per prime',
    (tester) async {
      final operaVecchia = await repo.aggiungiOpera(title: 'Il Corvo');
      final edizioneVecchia = await repo.aggiungiEdizione(
        operaId: operaVecchia,
        issueNumber: 1,
        publisher: 'Edizioni Meridiano',
      );
      await repo.aggiungiCopia(
        edizioneId: edizioneVecchia,
        status: StatoCopia.posseduta,
        createdAt: DateTime(2026),
      );

      final operaRecente = await repo.aggiungiOpera(title: 'Notturno');
      final edizioneRecente = await repo.aggiungiEdizione(operaId: operaRecente, issueNumber: 4);
      await repo.aggiungiCopia(
        edizioneId: edizioneRecente,
        status: StatoCopia.posseduta,
        createdAt: DateTime(2026, 6),
      );

      await pumpDashboard(tester);

      expect(find.text('AGGIUNTI DI RECENTE'), findsOneWidget);
      // Il titolo compare due volte per card: sulla copertina procedurale e
      // nell'etichetta sotto.
      expect(find.text('Notturno'), findsNWidgets(2));
      expect(find.text('Il Corvo'), findsNWidgets(2));
      expect(find.text('Edizioni Meridiano'), findsOneWidget);

      final xNotturno = tester.getTopLeft(find.text('Notturno').first).dx;
      final xCorvo = tester.getTopLeft(find.text('Il Corvo').first).dx;
      expect(xNotturno, lessThan(xCorvo));
    },
  );

  testWidgets(
    'sezione "Serie incomplete" mostra frazione, barra e numeri mancanti troncati oltre 3',
    (tester) async {
      // Titolo dell'opera diverso dal nome della serie, per non collidere
      // con il carosello "Aggiunti di recente" nelle asserzioni sotto.
      final opera = await repo.aggiungiOpera(title: 'Storia Sconosciuta');
      final serieId = await repo.aggiungiSerie(name: 'Kaiju Bianco', totalIssues: 5);
      for (final n in [1, 2, 3]) {
        final edizioneId = await repo.aggiungiEdizione(operaId: opera, serieId: serieId, issueNumber: n);
        await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);
      }
      // Mancano #4 e #5: sotto la soglia di troncamento (3), elencati per intero.

      await pumpDashboard(tester);

      expect(find.text('SERIE INCOMPLETE'), findsOneWidget);
      expect(find.text('Kaiju Bianco'), findsOneWidget);
      expect(find.text('3/5'), findsOneWidget);
      expect(find.text('Mancano #4, #5'), findsOneWidget);
      expect(find.byType(AppProgressBar), findsOneWidget);
    },
  );

  testWidgets(
    'carosello "Aggiunti di recente" mostra la cover reale se nota, non la copertina procedurale',
    (tester) async {
      final coverFile = File(
        '${Directory.systemTemp.path}/dashboard_cover_test_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      addTearDown(coverFile.delete);

      final operaId = await repo.aggiungiOpera(title: 'Con Cover');
      final edizioneId = await repo.aggiungiEdizione(operaId: operaId, coverImage: coverFile.path);
      await repo.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp(theme: AppTheme.dark, home: const DashboardPage()),
        ),
      );

      // Scrivere il file e far decodificare `Image.file` sono I/O reali (file,
      // isolate) — serve uscire dalla zona a tempo fittizio del test con
      // `runAsync`, altrimenti la callback di completamento non arriva mai
      // (si blocca indefinitamente), stesso problema di `revisione_page_test.dart`.
      await tester.runAsync(() async {
        // PNG 1x1 valido: basta perché Image.file lo decodifichi senza errore.
        await coverFile.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        );
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
      });

      // Con la cover reale il titolo compare una sola volta (etichetta sotto
      // la copertina): niente testo "Con Cover" disegnato sulla copertina
      // procedurale, sostituita da un'immagine.
      expect(find.text('Con Cover'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    },
  );
}
