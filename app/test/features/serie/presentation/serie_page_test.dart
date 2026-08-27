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
import 'package:mycomicbrain/features/serie/presentation/serie_page.dart';

/// Elenco `/serie` (§11, deciso su #97/#98): tre sezioni, righe compatte,
/// stato vuoto a schermo intero. Verificato con dati reali su un repository
/// in memoria — stessa convenzione di `scheda_page_test.dart`.
void main() {
  late AppDatabase db;
  late ComicsRepository repository;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    repository = ComicsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> edizioneConCopia({
    required String titolo,
    required int serieId,
    required int issueNumber,
    StatoCopia status = StatoCopia.posseduta,
  }) async {
    final operaId = await repository.aggiungiOpera(title: titolo);
    final edizioneId = await repository.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      issueNumber: issueNumber,
    );
    await repository.aggiungiCopia(edizioneId: edizioneId, status: status);
  }

  Future<void> pumpSerie(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/serie',
      routes: [
        GoRoute(path: '/serie', builder: (context, state) => const SeriePage()),
        GoRoute(
          path: '/serie/:id',
          builder: (context, state) => SerieDettaglioPage(
            serieId: int.parse(state.pathParameters['id']!),
          ),
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

  testWidgets('collezione senza serie: stato vuoto a schermo intero', (tester) async {
    await pumpSerie(tester);

    expect(find.text('Nessuna serie in collezione'), findsOneWidget);
    expect(find.text('Scansiona la prima cover'), findsOneWidget);
  });

  testWidgets('tre sezioni, ciascuna con conteggio e ordinamento corretti', (
    tester,
  ) async {
    final incompletaA = await repository.aggiungiSerie(
      name: 'A incompleta',
      totalIssues: 2,
    );
    await edizioneConCopia(titolo: 'A #1', serieId: incompletaA, issueNumber: 1);
    final incompletaB = await repository.aggiungiSerie(
      name: 'B incompleta',
      totalIssues: 4,
    );
    await edizioneConCopia(titolo: 'B #1', serieId: incompletaB, issueNumber: 1);

    final completaZeta = await repository.aggiungiSerie(
      name: 'Zeta completa',
      totalIssues: 1,
    );
    await edizioneConCopia(titolo: 'Zeta #1', serieId: completaZeta, issueNumber: 1);

    final senzaTotale = await repository.aggiungiSerie(name: 'Rho senza totale');
    await edizioneConCopia(titolo: 'Rho #1', serieId: senzaTotale, issueNumber: 1);

    await pumpSerie(tester);

    // SectionHeader maiuscolizza l'etichetta.
    expect(find.text('INCOMPLETE · 2'), findsOneWidget);
    expect(find.text('COMPLETE · 1'), findsOneWidget);
    expect(find.text('SENZA NUMERO TOTALE · 1'), findsOneWidget);

    // "B incompleta" (25%) prima di "A incompleta" (50%) — ordine per
    // percentuale crescente (#97).
    final bY = tester.getTopLeft(find.text('B incompleta')).dy;
    final aY = tester.getTopLeft(find.text('A incompleta')).dy;
    expect(bY, lessThan(aY));
  });

  testWidgets('tap su una riga apre il dettaglio della serie', (tester) async {
    final serieId = await repository.aggiungiSerie(
      name: 'Kaiju Bianco',
      totalIssues: 5,
    );
    await edizioneConCopia(titolo: 'Kaiju #1', serieId: serieId, issueNumber: 1);

    await pumpSerie(tester);
    await tester.tap(find.text('Kaiju Bianco'));
    await tester.pumpAndSettle();

    // Il dettaglio mostra editore/anno/issn assenti, ma il titolo e le
    // statistiche identificano senza ambiguità che siamo sulla pagina giusta.
    expect(find.text('posseduti'), findsOneWidget);
    expect(find.text('duplicati'), findsOneWidget);
  });
}
