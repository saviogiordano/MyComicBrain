import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';
import 'package:mycomicbrain/features/scheda/presentation/modifica_copia_sheet.dart';
import 'package:mycomicbrain/features/scheda/presentation/modifica_scheda_page.dart';

/// Il cambio della cover passa dall'editor di ritaglio delle Scansioni, e
/// le Note della Copia mostrano tutte le righe.
void main() {
  late AppDatabase db;
  late DriftComicsRepository repository;
  late Directory tempBase;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    tempBase = await Directory.systemTemp.createTemp('modifica_cover_');
    repository = DriftComicsRepository(
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

  /// Pompa la pagina di modifica dell'Edizione. [ritaglia] sostituisce
  /// galleria + editor di ritaglio.
  Future<String> pumpModifica(
    WidgetTester tester, {
    required Future<String?> Function(ImageSource) ritaglia,
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final edizioneId = (await tester.runAsync(
      () async => repository.aggiungiEdizione(
        operaId: await repository.aggiungiOpera(title: 'Batman'),
        issueNumberLabel: '1',
        coverImage: 'copertine/originale.jpg',
      ),
    ))!;

    final router = GoRouter(
      initialLocation: '/scheda/$edizioneId',
      routes: [
        // Salvare torna indietro: serve una pagina sotto.
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
          builder: (context, state) =>
              ModificaSchedaPage(edizioneId: state.pathParameters['id']!),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicsRepositoryProvider.overrideWithValue(repository),
          scegliCoverRitagliataProvider.overrideWithValue(ritaglia),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.tap(find.text('vai'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    return edizioneId;
  }

  /// Lascia avanzare l'I/O vero (copia dei file, drift) alternandolo ai
  /// frame: le sue continuazioni girano nella zona finta del test.
  Future<void> attendiIO(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> scegliDallaGalleria(WidgetTester tester) async {
    await tester.tap(find.text('Cambia cover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scegli dalla galleria'));
    // Copia del file in copertine/: I/O vero.
    await attendiIO(tester);
  }

  Future<String?> salvaECover(WidgetTester tester, String edizioneId) async {
    await tester.tap(find.text('Salva'));
    await attendiIO(tester);
    return tester.runAsync<String?>(
      () => repository.coverImageGrezzoDi(edizioneId),
    );
  }

  testWidgets('la nuova cover passa dal ritaglio e diventa quella '
      'ritagliata', (tester) async {
    final ritagliata = File('${tempBase.path}/ritagliata.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final sorgenti = <ImageSource>[];
    final edizioneId = await pumpModifica(
      tester,
      ritaglia: (sorgente) async {
        sorgenti.add(sorgente);
        return ritagliata.path;
      },
    );

    await scegliDallaGalleria(tester);
    final cover = await salvaECover(tester, edizioneId);

    expect(sorgenti, [ImageSource.gallery]);
    expect(cover, isNot('copertine/originale.jpg'));
    expect(cover, startsWith('copertine/'));
    expect(File('${tempBase.path}/$cover').readAsBytesSync(), [1, 2, 3]);
    expect(
      ritagliata.existsSync(),
      isFalse,
      reason: 'il temporaneo del ritaglio si ripulisce',
    );
  });

  testWidgets("annullare il ritaglio lascia la cover com'era", (
    tester,
  ) async {
    final edizioneId = await pumpModifica(
      tester,
      ritaglia: (_) async => null,
    );

    await scegliDallaGalleria(tester);

    expect(await salvaECover(tester, edizioneId), 'copertine/originale.jpg');
  });

  testWidgets('se la foto non riesce lo dice e la cover resta', (
    tester,
  ) async {
    final edizioneId = await pumpModifica(
      tester,
      ritaglia: (_) async => throw Exception('permesso negato'),
    );

    await tester.tap(find.text('Cambia cover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scatta una foto'));
    await attendiIO(tester);

    expect(find.text('Foto non riuscita, riprova'), findsOneWidget);
    expect(await salvaECover(tester, edizioneId), 'copertine/originale.jpg');
  });

  testWidgets("la Descrizione dell'Edizione mostra tutte le righe", (
    tester,
  ) async {
    await pumpModifica(tester, ritaglia: (_) async => null);

    final campo = tester.widget<TextField>(
      find.byKey(const Key('campo-descrizione')),
    );
    expect(campo.maxLines, isNull, reason: 'il campo cresce con il testo');
    expect(campo.keyboardType, TextInputType.multiline);
  });

  testWidgets('le Note della Copia mostrano tutte le righe', (tester) async {
    const note = 'prima riga\nseconda riga\nterza riga\nquarta riga';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [comicsRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => mostraModificaCopiaSheet(
                context,
                copia: const CopiaDettaglio(
                  id: 'c1',
                  status: StatoCopia.posseduta,
                  notes: note,
                ),
              ),
              child: const Text('apri'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    final campo = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == note,
      ),
    );
    expect(campo.maxLines, isNull, reason: 'il campo cresce con il testo');
    expect(campo.keyboardType, TextInputType.multiline);
  });
}
