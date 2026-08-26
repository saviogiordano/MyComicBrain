import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/scansione_storage.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/scansione/presentation/revisione_page.dart';
import 'package:mycomicbrain/features/scansione/presentation/riepilogo_page.dart';
import 'package:mycomicbrain/features/scansione/presentation/scansione_page.dart';
import 'package:path/path.dart' as p;

void main() {
  const scannerChannel = MethodChannel('cunning_document_scanner');
  const permissionChannel = MethodChannel('flutter.baseflow.com/permissions/methods');

  // Codici di `PermissionStatus` (permission_handler_platform_interface):
  // denied=0, granted=1, restricted=2, limited=3, permanentlyDenied=4.
  const statusDenied = 0;
  const statusPermanentlyDenied = 4;

  var permissionStatus = statusDenied;
  var openAppSettingsCalls = 0;

  // Handler di default per il canale dello scanner: sovrascritto nei singoli
  // test che devono simulare un annullamento, un risultato o un errore.
  Future<Object?> Function(MethodCall) scannerHandler = (call) async => null;

  setUp(() {
    permissionStatus = statusDenied;
    openAppSettingsCalls = 0;
    scannerHandler = (call) async => null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, (call) => scannerHandler(call));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
          switch (call.method) {
            case 'checkPermissionStatus':
              return permissionStatus;
            case 'openAppSettings':
              openAppSettingsCalls++;
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
  });

  Future<void> pumpScanner(
    WidgetTester tester, {
    List<Override> overrides = const [],
    Widget Function(BuildContext, GoRouterState)? revisioneBuilder,
  }) async {
    final router = GoRouter(
      initialLocation: '/scansione',
      routes: [
        GoRoute(path: '/scansione', builder: (context, state) => const ScansionePage()),
        GoRoute(
          path: '/scansione/revisione',
          builder:
              revisioneBuilder ??
              (context, state) => RevisionePage(percorsiGrezzi: state.extra! as List<String>),
        ),
        GoRoute(
          path: '/scansione/riepilogo',
          builder: (context, state) =>
              RiepilogoPage(scansioni: state.extra! as List<XFile>),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(overrides: overrides, child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapFotocamera(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Fotocamera'));
    await tester.pumpAndSettle();
  }

  testWidgets('stato iniziale mostra il messaggio neutro, "Nessuna scansione ancora" e il bottone Fotocamera', (
    tester,
  ) async {
    await pumpScanner(tester);

    expect(find.text('Scansiona una cover'), findsOneWidget);
    expect(find.text('Tocca "Fotocamera" per aprire lo scanner'), findsOneWidget);
    expect(find.text('Nessuna scansione ancora'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Fotocamera'), findsOneWidget);
  });

  testWidgets('annullamento dello scanner (null) non mostra errori e resta nello stato iniziale', (tester) async {
    await pumpScanner(tester);
    scannerHandler = (call) async => null;

    await tapFotocamera(tester);

    expect(find.text('Scansiona una cover'), findsOneWidget);
    expect(find.text('Nessuna scansione ancora'), findsOneWidget);
  });

  testWidgets('permesso negato in modo permanente mostra "Apri Impostazioni" senza invocare lo scanner', (
    tester,
  ) async {
    permissionStatus = statusPermanentlyDenied;
    var scannerInvocato = false;
    scannerHandler = (call) async {
      scannerInvocato = true;
      return null;
    };

    await pumpScanner(tester);
    await tapFotocamera(tester);

    expect(find.text('Permesso fotocamera negato'), findsOneWidget);
    expect(find.text('Attivalo dalle Impostazioni, oppure usa la Galleria'), findsOneWidget);
    expect(scannerInvocato, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Apri Impostazioni'));
    await tester.pumpAndSettle();

    expect(openAppSettingsCalls, 1);
  });

  testWidgets('un errore del plugin non di permesso mostra uno SnackBar riprovabile', (tester) async {
    scannerHandler = (call) async {
      throw PlatformException(code: 'ALREADY_ACTIVE', message: 'Scanner already active');
    };

    await pumpScanner(tester);
    await tapFotocamera(tester);

    expect(find.text('Scansione non riuscita, riprova'), findsOneWidget);
    expect(find.text('Permesso fotocamera negato'), findsNothing);
  });

  testWidgets('un diniego di permesso segnalato dal plugin a permesso ormai permanente mostra "Apri Impostazioni"', (
    tester,
  ) async {
    scannerHandler = (call) async {
      // Il diniego arriva dal componente nativo dopo il check anticipato:
      // simula che nel frattempo il permesso sia diventato permanente.
      permissionStatus = statusPermanentlyDenied;
      throw PlatformException(code: 'permission_denied', message: 'Permission not granted');
    };

    await pumpScanner(tester);
    await tapFotocamera(tester);

    expect(find.text('Permesso fotocamera negato'), findsOneWidget);
  });

  testWidgets(
    'una scansione riuscita copia i file in storage permanente, ripulisce la cache del plugin '
    'e apre la revisione con i nuovi percorsi permanenti (#89)',
    (tester) async {
      // La creazione della directory temporanea è I/O reale: va fatta
      // dentro `runAsync`, non nel corpo diretto di `testWidgets` (che gira
      // nella zona a tempo fittizio) — altrimenti resta sospesa per sempre,
      // dato che quella zona non fa avanzare l'I/O reale.
      late Directory tempDir;
      late File grezzo;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('scansione_page_test_');
        grezzo = File(p.join(tempDir.path, 'cache_plugin', 'pagina1.jpg'))
          ..createSync(recursive: true)
          ..writeAsStringSync('contenuto scansionato');
      });
      addTearDown(() => tempDir.deleteSync(recursive: true));

      var cleanCacheChiamato = false;
      scannerHandler = (call) async {
        if (call.method == 'cleanCache') {
          cleanCacheChiamato = true;
          return null;
        }
        return [grezzo.path];
      };

      List<String>? percorsiRicevutiDaRevisione;
      await pumpScanner(
        tester,
        overrides: [
          scansioneStorageProvider.overrideWithValue(ScansioneStorage(baseDirectory: () async => tempDir)),
        ],
        // Stub della revisione: l'editor nativo di image_cropper non è
        // mockato in questo file, e non serve — questo test verifica solo
        // che ScansionePage copi i grezzi in storage permanente e passi
        // quei nuovi percorsi (non quelli nella cache del plugin).
        revisioneBuilder: (context, state) {
          percorsiRicevutiDaRevisione = state.extra! as List<String>;
          return const Scaffold(body: Text('stub revisione'));
        },
      );

      // Né `pumpAndSettle` (la revisione resta aperta: lo stub non fa mai
      // pop, quindi `ScansionePage` sottostante resta bloccato con lo
      // spinner indeterminato del bottone "Fotocamera", che non si
      // "assesta" mai da solo) né un semplice `pump` bastano: `salvaGrezzi`
      // fa I/O reale su file, che serve `runAsync` per drenare (stesso
      // pattern di `revisione_page_test.dart`).
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Fotocamera'));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump(const Duration(milliseconds: 20));
        }
      });

      expect(find.text('stub revisione'), findsOneWidget);
      expect(cleanCacheChiamato, isTrue);
      expect(percorsiRicevutiDaRevisione, hasLength(1));
      expect(
        percorsiRicevutiDaRevisione!.single,
        isNot(grezzo.path),
        reason: 'deve usare la copia permanente, non il file nella cache del plugin',
      );
      expect(File(percorsiRicevutiDaRevisione!.single).readAsStringSync(), 'contenuto scansionato');
      expect(p.dirname(percorsiRicevutiDaRevisione!.single), p.join(tempDir.path, 'scansioni_grezze'));
    },
  );

  testWidgets('"Fine" naviga al riepilogo di fine batch (vuoto, nessuna Scansione confermata)', (tester) async {
    await pumpScanner(tester);

    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();

    expect(find.text('Riepilogo batch'), findsOneWidget);
    expect(find.text('0 scansioni pronte per il riconoscimento AI'), findsOneWidget);
  });
}
