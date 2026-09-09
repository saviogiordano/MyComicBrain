import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
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
import 'package:mycomicbrain/features/scheda/presentation/modifica_scheda_page.dart';

/// Nella app reale `driftDatabase(...)` (vedi `database.dart`) esegue le
/// query su un isolate separato: `coverImageGrezzoDi` (il fetch del path
/// *relativo* della cover, avviato senza await da `_prefill`) non è quindi
/// mai istantaneo come lo è con `NativeDatabase.memory()` nello stesso
/// isolate usato dagli altri test. Questo repository di test introduce
/// artificialmente lo stesso ritardo, gated da un `Completer` controllato
/// dal test, per riprodurre deterministicamente la finestra in cui l'utente
/// può toccare "Salva" prima che il fetch sia arrivato.
class _RepositoryConFetchCoverLento extends ComicsRepository {
  _RepositoryConFetchCoverLento(super.db, {required super.copertinaDownloader});

  final gate = Completer<void>();

  @override
  Future<String?> coverImageGrezzoDi(int edizioneId) async {
    await gate.future;
    return super.coverImageGrezzoDi(edizioneId);
  }
}

void main() {
  late AppDatabase db;
  late _RepositoryConFetchCoverLento repository;
  late Directory tempBase;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    tempBase = await Directory.systemTemp.createTemp(
      'modifica_scheda_page_test_',
    );
    repository = _RepositoryConFetchCoverLento(
      db,
      copertinaDownloader: CopertinaDownloader(
        baseDirectory: () async => tempBase,
      ),
    );
  });

  tearDown(() async {
    if (!repository.gate.isCompleted) repository.gate.complete();
    await db.close();
    await tempBase.delete(recursive: true);
  });

  Future<int> edizioneConCover() async {
    final operaId = await repository.aggiungiOpera(title: 'Batman');
    return repository.aggiungiEdizione(
      operaId: operaId,
      issueNumber: 1,
      issueNumberLabel: '1',
      coverImage: 'copertine/originale.jpg',
    );
  }

  Future<void> pumpModifica(WidgetTester tester, {required int edizioneId}) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/scheda/$edizioneId',
      routes: [
        GoRoute(
          path: '/scheda/:id',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/scheda/$edizioneId/modifica'),
                child: const Text('vai'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/scheda/:id/modifica',
          builder: (context, state) => ModificaSchedaPage(
            edizioneId: int.parse(state.pathParameters['id']!),
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
    await tester.tap(find.text('vai'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'salvare prima che il fetch del path relativo della cover sia arrivato '
    'non deve cancellare la cover esistente',
    (tester) async {
      final edizioneId = await edizioneConCover();

      await pumpModifica(tester, edizioneId: edizioneId);

      // Il fetch di coverImageGrezzoDi (gated) non è ancora arrivato: la
      // pagina è comunque già interattiva (stessa UX reale — la preview
      // della cover si vede già, presa dal valore risolto della stream, non
      // dal fetch lento) e "Salva" è abilitato.
      expect(find.text('Salva'), findsOneWidget);

      // L'utente cambia solo il numero, come nel bug segnalato, e salva
      // subito.
      await tester.enterText(find.byKey(const Key('campo-numero')), '2');
      await tester.tap(find.text('Salva'));
      await tester.pump();

      // Solo ora arriva il fetch lento — troppo tardi rispetto al tap, ma
      // non deve più essere troppo tardi rispetto alla scrittura: la fix
      // deve aspettarlo prima di chiamare aggiornaEdizione.
      repository.gate.complete();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final coverImageSalvato = await repository.coverImageGrezzoDi(edizioneId);
      expect(
        coverImageSalvato,
        'copertine/originale.jpg',
        reason:
            'la cover esistente non deve sparire solo perché il numero è '
            'stato modificato',
      );
    },
  );
}
