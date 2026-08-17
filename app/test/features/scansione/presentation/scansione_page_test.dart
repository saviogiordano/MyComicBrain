import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/scansione/presentation/scansione_page.dart';

void main() {
  const cameraChannel = MethodChannel('plugins.flutter.io/camera');

  setUp(() {
    // Simula un device senza fotocamere (es. Simulator, vedi
    // docs/research/camera-package-flutter.md §6) — esercita il fallback
    // senza dipendere da un vero canale platform-specifico.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, (call) async {
          if (call.method == 'availableCameras') return <Map<String, Object?>>[];
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, null);
  });

  Future<void> pumpScanner(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/scansione',
      routes: [
        GoRoute(path: '/scansione', builder: (context, state) => const ScansionePage()),
        GoRoute(
          path: '/scansione/revisione',
          builder: (context, state) =>
              const PlaceholderScreen(title: 'Revisione', icon: Icons.crop_rotate_outlined),
        ),
        GoRoute(
          path: '/scansione/riepilogo',
          builder: (context, state) =>
              const PlaceholderScreen(title: 'Riepilogo', icon: Icons.checklist_outlined),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('senza fotocamera mostra il fallback e il primo suggerimento (1/5)', (tester) async {
    await pumpScanner(tester);

    expect(find.text('Fotocamera non disponibile'), findsOneWidget);
    expect(find.text('Nessuna scansione ancora'), findsOneWidget);
    expect(find.text('Inquadra tutta la copertina'), findsOneWidget);
    expect(find.text('1/5'), findsOneWidget);
  });

  testWidgets('il tocco sulla pillola avanza al suggerimento successivo', (tester) async {
    await pumpScanner(tester);

    await tester.tap(find.text('Inquadra tutta la copertina'));
    await tester.pumpAndSettle();

    expect(find.text('Allinea la copertina dritta'), findsOneWidget);
    expect(find.text('2/5'), findsOneWidget);
  });

  testWidgets('"Fine" naviga allo stub del riepilogo di fine batch', (tester) async {
    await pumpScanner(tester);

    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();

    expect(find.text('Riepilogo'), findsOneWidget);
    expect(find.text('In arrivo'), findsOneWidget);
  });
}
