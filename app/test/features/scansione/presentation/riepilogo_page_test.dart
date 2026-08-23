import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/analisi_copertina_pipeline.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/scansione/presentation/riepilogo_page.dart';
import 'package:path/path.dart' as p;

/// Sostituisce la pipeline reale (rete/DB) nei test: registra i batch
/// ricevuti da "Fine" invece di chiamare Claude davvero.
class _FakeAnalisiCopertinaPipeline implements AnalisiCopertinaPipeline {
  final batchRicevuti = <List<String>>[];
  final riprovati = <String>[];

  @override
  Future<void> avviaBatch(Iterable<String> percorsiImmagine) async {
    batchRicevuti.add(percorsiImmagine.toList());
  }

  @override
  Future<void> riprova(String percorsoImmagine) async {
    riprovati.add(percorsoImmagine);
  }
}

// PNG 1x1 valido: basta a far decodere `Image.file` senza errori nei test.
const _pngMinimo = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x04,
  0x00,
  0x00,
  0x00,
  0xB5,
  0x1C,
  0x0C,
  0x02,
  0x00,
  0x00,
  0x00,
  0x0B,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x64,
  0x00,
  0x04,
  0x00,
  0x00,
  0x06,
  0x00,
  0x02,
  0x30,
  0x81,
  0xD0,
  0x2F,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('riepilogo_page_test_');
  });

  tearDown(() => tempDir.delete(recursive: true));

  List<XFile> scansioniFinte(int n) => [
    for (var i = 0; i < n; i++)
      XFile(
        (File(
          p.join(tempDir.path, 'scan_$i.jpg'),
        )..writeAsBytesSync(_pngMinimo)).path,
      ),
  ];

  Future<GoRouter> pumpRiepilogo(
    WidgetTester tester,
    List<XFile> scansioni, {
    AnalisiCopertinaPipeline? pipeline,
    ComicsRepository? repository,
  }) async {
    final router = GoRouter(
      initialLocation: '/scansione',
      routes: [
        GoRoute(
          path: '/scansione',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    context.push('/scansione/riepilogo', extra: scansioni),
                child: const Text('vai al riepilogo'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/scansione/riepilogo',
          builder: (context, state) =>
              RiepilogoPage(scansioni: state.extra! as List<XFile>),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Dashboard'))),
        ),
        GoRoute(
          path: '/scansione/conferma-candidato',
          builder: (context, state) => Scaffold(
            body: Center(
              child: Text('Conferma candidato · Scansione ${state.extra}'),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (pipeline != null)
            analisiCopertinaPipelineProvider.overrideWithValue(pipeline),
          if (repository != null)
            comicsRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.tap(find.text('vai al riepilogo'));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('mostra una riga per Scansione con chip "In sospeso"', (
    tester,
  ) async {
    await pumpRiepilogo(tester, scansioniFinte(2));

    expect(
      find.text('2 scansioni pronte per il riconoscimento AI'),
      findsOneWidget,
    );
    expect(find.text('Scansione 1'), findsOneWidget);
    expect(find.text('Scansione 2'), findsOneWidget);
    expect(find.text('In sospeso'), findsNWidgets(2));
  });

  testWidgets('"Aggiungi altre" torna allo scanner (batch preservato)', (
    tester,
  ) async {
    await pumpRiepilogo(tester, scansioniFinte(1));

    await tester.tap(find.text('Aggiungi altre'));
    await tester.pumpAndSettle();

    expect(find.text('vai al riepilogo'), findsOneWidget);
    expect(find.text('Riepilogo batch'), findsNothing);
  });

  testWidgets(
    '"Fine" avvia la pipeline ma resta sul riepilogo; "Vai alla Dashboard" naviga davvero (#59)',
    (tester) async {
      await pumpRiepilogo(
        tester,
        scansioniFinte(1),
        pipeline: _FakeAnalisiCopertinaPipeline(),
      );

      await tester.tap(find.text('Fine'));
      await tester.pumpAndSettle();

      expect(
        find.text('Riepilogo batch'),
        findsOneWidget,
        reason:
            'resta sul riepilogo per vedere gli stati e la conferma candidato (#59)',
      );
      expect(find.text('Fine'), findsNothing);
      expect(find.text('Vai alla Dashboard'), findsOneWidget);

      await tester.tap(find.text('Vai alla Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Riepilogo batch'), findsNothing);
    },
  );

  testWidgets(
    'la chip riflette lo stato reale invece di restare "In sospeso"',
    (tester) async {
      final db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(db.close);
      final repository = ComicsRepository(db);
      final scansioni = scansioniFinte(1);
      await repository.aggiungiScansione(image: scansioni.single.path);

      await pumpRiepilogo(tester, scansioni, repository: repository);
      expect(find.text('In sospeso'), findsOneWidget);

      final scansioneId = await repository.idScansionePerImmagine(
        scansioni.single.path,
      );
      final analisiId = await repository.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );
      await tester.pumpAndSettle();
      expect(find.text('In corso'), findsOneWidget);
      expect(find.text('In sospeso'), findsNothing);

      await repository.completaAnalisiCopertina(
        id: analisiId,
        rawResponse: '{}',
      );
      await tester.pumpAndSettle();
      expect(find.text('Completata'), findsOneWidget);
    },
  );

  testWidgets('la chip "Fallita" è il tasto di retry manuale', (tester) async {
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    final repository = ComicsRepository(db);
    final scansioni = scansioniFinte(1);
    await repository.aggiungiScansione(image: scansioni.single.path);
    final scansioneId = await repository.idScansionePerImmagine(
      scansioni.single.path,
    );
    final analisiId = await repository.avviaAnalisiCopertina(
      scansioneId: scansioneId,
    );
    await repository.fallisciAnalisiCopertina(
      id: analisiId,
      errorMessage: 'timeout',
    );

    final pipeline = _FakeAnalisiCopertinaPipeline();
    await pumpRiepilogo(
      tester,
      scansioni,
      pipeline: pipeline,
      repository: repository,
    );

    expect(find.textContaining('Fallita'), findsOneWidget);

    await tester.tap(find.textContaining('Fallita'));
    await tester.pumpAndSettle();

    expect(pipeline.riprovati, [scansioni.single.path]);
  });

  testWidgets(
    'una riga con Analisi Copertina completata apre la conferma candidato al tocco (#59)',
    (tester) async {
      final db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(db.close);
      final repository = ComicsRepository(db);
      final scansioni = scansioniFinte(1);
      await repository.aggiungiScansione(image: scansioni.single.path);
      final scansioneId = await repository.idScansionePerImmagine(
        scansioni.single.path,
      );
      final analisiId = await repository.avviaAnalisiCopertina(
        scansioneId: scansioneId,
      );

      await pumpRiepilogo(tester, scansioni, repository: repository);
      await tester.tap(find.byType(AppCard));
      await tester.pumpAndSettle();
      expect(
        find.text('Riepilogo batch'),
        findsOneWidget,
        reason: 'ancora non completata: nessuna navigazione',
      );

      await repository.completaAnalisiCopertina(
        id: analisiId,
        rawResponse: '{}',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppCard));
      await tester.pumpAndSettle();

      expect(
        find.text('Conferma candidato · Scansione $scansioneId'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'swipe-to-delete rimuove la scansione (file e riga DB) prima di "Fine" (#59)',
    (tester) async {
      final db = AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(db.close);
      final repository = ComicsRepository(db);
      final scansioni = scansioniFinte(2);
      for (final s in scansioni) {
        await repository.aggiungiScansione(image: s.path);
      }

      await pumpRiepilogo(tester, scansioni, repository: repository);
      expect(
        find.text('2 scansioni pronte per il riconoscimento AI'),
        findsOneWidget,
      );

      // `ScansioneStorage.elimina` fa vera I/O su file (`dart:io`): serve
      // `runAsync` perché quella Future non si risolve nella zona
      // fake-async di default di `testWidgets` — e un breve delay reale
      // dopo l'ultimo `pumpAndSettle` perché quella I/O parte da
      // `onDismissed` (fire-and-forget) e non è legata a un frame
      // schedulato, quindi `pumpAndSettle` da solo non la aspetta.
      await tester.runAsync(() async {
        await tester.drag(
          find.byType(Dismissible).first,
          const Offset(-500, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rimuovi'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      expect(
        find.text('1 scansione pronta per il riconoscimento AI'),
        findsOneWidget,
      );
      final righeRimaste = await db.select(db.scansioni).get();
      expect(righeRimaste, hasLength(1));
      expect(File(scansioni.first.path).existsSync(), isFalse);
    },
  );

  testWidgets('annullare la conferma di eliminazione non rimuove nulla', (
    tester,
  ) async {
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    final repository = ComicsRepository(db);
    final scansioni = scansioniFinte(1);
    await repository.aggiungiScansione(image: scansioni.single.path);

    await pumpRiepilogo(tester, scansioni, repository: repository);

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(find.text('Scansione 1'), findsOneWidget);
    final righe = await db.select(db.scansioni).get();
    expect(righe, hasLength(1));
    expect(File(scansioni.single.path).existsSync(), isTrue);
  });

  testWidgets('dopo "Fine" lo swipe-to-delete è disabilitato', (
    tester,
  ) async {
    await pumpRiepilogo(
      tester,
      scansioniFinte(1),
      pipeline: _FakeAnalisiCopertinaPipeline(),
    );

    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();

    expect(find.byType(Dismissible), findsNothing);
  });

  testWidgets(
    "'Fine' avvia la pipeline di analisi copertina sull'intero batch",
    (tester) async {
      final pipeline = _FakeAnalisiCopertinaPipeline();
      final scansioni = scansioniFinte(2);

      await pumpRiepilogo(tester, scansioni, pipeline: pipeline);
      await tester.tap(find.text('Fine'));
      await tester.pumpAndSettle();

      expect(pipeline.batchRicevuti, [
        [for (final s in scansioni) s.path],
      ]);
    },
  );
}
