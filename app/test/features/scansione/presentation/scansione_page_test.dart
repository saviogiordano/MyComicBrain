import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/scansione/presentation/revisione_page.dart';
import 'package:mycomicbrain/features/scansione/presentation/riepilogo_page.dart';
import 'package:mycomicbrain/features/scansione/presentation/scansione_page.dart';

void main() {
  const cameraChannel = MethodChannel('plugins.flutter.io/camera');
  const permissionChannel = MethodChannel('flutter.baseflow.com/permissions/methods');

  // Codici di `PermissionStatus` (permission_handler_platform_interface):
  // denied=0, granted=1, restricted=2, limited=3, permanentlyDenied=4.
  const statusDenied = 0;
  const statusPermanentlyDenied = 4;

  var permissionStatus = statusDenied;
  var openAppSettingsCalls = 0;

  setUp(() {
    permissionStatus = statusDenied;
    openAppSettingsCalls = 0;

    // Simula un device senza fotocamere (es. Simulator, vedi
    // docs/research/camera-package-flutter.md §6) — esercita il fallback
    // senza dipendere da un vero canale platform-specifico.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, (call) async {
          if (call.method == 'availableCameras') return <Map<String, Object?>>[];
          return null;
        });

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
        .setMockMethodCallHandler(cameraChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
  });

  Future<void> pumpScanner(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/scansione',
      routes: [
        GoRoute(path: '/scansione', builder: (context, state) => const ScansionePage()),
        GoRoute(
          path: '/scansione/revisione',
          builder: (context, state) =>
              RevisionePage(percorsiGrezzi: state.extra! as List<String>),
        ),
        GoRoute(
          path: '/scansione/riepilogo',
          builder: (context, state) =>
              RiepilogoPage(scansioni: state.extra! as List<XFile>),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('senza fotocamera mostra il fallback riprovabile e il primo suggerimento (1/6)', (tester) async {
    await pumpScanner(tester);

    expect(find.text('Fotocamera non disponibile'), findsOneWidget);
    expect(find.text('Puoi riprovare o usare la Galleria'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Riprova'), findsOneWidget);
    expect(find.text('Nessuna scansione ancora'), findsOneWidget);
    expect(find.text('Inquadra tutta la copertina'), findsOneWidget);
    expect(find.text('1/6'), findsOneWidget);
  });

  testWidgets('"Riprova" ricontrolla il permesso e reinizializza la fotocamera', (tester) async {
    await pumpScanner(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Riprova'));
    await tester.pumpAndSettle();

    // Ancora nessuna fotocamera disponibile: resta nello stato riprovabile.
    expect(find.text('Fotocamera non disponibile'), findsOneWidget);
  });

  testWidgets('permesso negato in modo permanente mostra "Apri Impostazioni"', (tester) async {
    permissionStatus = statusPermanentlyDenied;

    await pumpScanner(tester);

    expect(find.text('Permesso fotocamera negato'), findsOneWidget);
    expect(find.text('Attivalo dalle Impostazioni, oppure usa la Galleria'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Apri Impostazioni'));
    await tester.pumpAndSettle();

    expect(openAppSettingsCalls, 1);
  });

  testWidgets('il tocco sulla pillola avanza al suggerimento successivo', (tester) async {
    await pumpScanner(tester);

    await tester.tap(find.text('Inquadra tutta la copertina'));
    await tester.pumpAndSettle();

    expect(find.text('Allinea la copertina dritta'), findsOneWidget);
    expect(find.text('2/6'), findsOneWidget);
  });

  testWidgets('"Fine" naviga al riepilogo di fine batch (vuoto, nessuna Scansione confermata)', (tester) async {
    await pumpScanner(tester);

    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();

    expect(find.text('Riepilogo batch'), findsOneWidget);
    expect(find.text('0 scansioni pronte per il riconoscimento AI'), findsOneWidget);
  });
}
