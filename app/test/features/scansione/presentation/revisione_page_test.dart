import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/image_crop_service.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/scansione_storage.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/scansione/presentation/revisione_page.dart';
import 'package:path/path.dart' as p;

// PNG 1x1 valido: basta a far decodere `Image.file` senza errori nei test.
const _pngMinimo = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x04, 0x00, 0x00, 0x00, 0xB5, 0x1C, 0x0C,
  0x02, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x64, 0x00, 0x04, 0x00,
  0x00, 0x06, 0x00, 0x02, 0x30, 0x81, 0xD0, 0x2F, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late Directory tempDir;
  late AppDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('revisione_page_test_');
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  File scriviFinta(String nome) => File(p.join(tempDir.path, nome))..writeAsBytesSync(_pngMinimo);

  Future<List<XFile>?> pumpEAvvia(
    WidgetTester tester, {
    required List<String> percorsiGrezzi,
    required ImageCropService cropService,
  }) async {
    List<XFile>? risultato;
    final router = GoRouter(
      initialLocation: '/scansione',
      routes: [
        GoRoute(
          path: '/scansione',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  risultato = await context.push<List<XFile>>('/scansione/revisione', extra: percorsiGrezzi);
                },
                child: const Text('avvia'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/scansione/revisione',
          builder: (context, state) => RevisionePage(percorsiGrezzi: state.extra! as List<String>),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          imageCropServiceProvider.overrideWithValue(cropService),
          scansioneStorageProvider.overrideWithValue(ScansioneStorage(baseDirectory: () async => tempDir)),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    // La coda di revisione fa I/O reale (file, DB) — serve uscire dalla zona
    // a tempo fittizio del test widget per farla completare. `pumpAndSettle`
    // non è utilizzabile: lo spinner indeterminato non si "assesta" mai da
    // solo, quindi si pompano un numero di frame fisso finché il risultato
    // non arriva.
    await tester.runAsync(() async {
      await tester.tap(find.text('avvia'));
      for (var i = 0; i < 50 && risultato == null; i++) {
        // Il delay reale (non solo `pump`) lascia drenare l'event loop vero
        // così le callback di I/O reale (file, drift nativo) arrivano.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
    });

    return risultato;
  }

  testWidgets('conferma: salva la Scansione e ripulisce il grezzo', (tester) async {
    final grezzo = scriviFinta('grezzo.jpg');
    final ritagliato = scriviFinta('ritagliato.jpg');

    final risultato = await pumpEAvvia(
      tester,
      percorsiGrezzi: [grezzo.path],
      cropService: ImageCropService(ritaglia: (_) async => ritagliato.path),
    );

    expect(risultato, hasLength(1));
    expect(grezzo.existsSync(), isFalse, reason: 'il grezzo pre-ritaglio va ripulito');

    final scansioni = await db.select(db.scansioni).get();
    expect(scansioni, hasLength(1));
    expect(scansioni.single.image, risultato!.single.path);
  });

  testWidgets('riscatta: nessuna Scansione creata, ma il grezzo viene comunque ripulito', (tester) async {
    final grezzo = scriviFinta('grezzo.jpg');

    final risultato = await pumpEAvvia(
      tester,
      percorsiGrezzi: [grezzo.path],
      cropService: ImageCropService(ritaglia: (_) async => null),
    );

    expect(risultato, isEmpty);
    expect(grezzo.existsSync(), isFalse);
    expect(await db.select(db.scansioni).get(), isEmpty);
  });

  testWidgets("coda di più foto: ognuna passa per l'editor, solo le confermate tornano", (tester) async {
    final grezzo1 = scriviFinta('grezzo1.jpg');
    final grezzo2 = scriviFinta('grezzo2.jpg');
    final ritagliato2 = scriviFinta('ritagliato2.jpg');

    final percorsiVisti = <String>[];
    final risultato = await pumpEAvvia(
      tester,
      percorsiGrezzi: [grezzo1.path, grezzo2.path],
      cropService: ImageCropService(
        ritaglia: (path) async {
          percorsiVisti.add(path);
          return path == grezzo1.path ? null : ritagliato2.path;
        },
      ),
    );

    expect(percorsiVisti, [grezzo1.path, grezzo2.path]);
    expect(risultato, hasLength(1));
    expect(await db.select(db.scansioni).get(), hasLength(1));
  });
}
