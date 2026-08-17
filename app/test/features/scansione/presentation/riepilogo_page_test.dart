import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/scansione/presentation/riepilogo_page.dart';
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('riepilogo_page_test_');
  });

  tearDown(() => tempDir.delete(recursive: true));

  List<XFile> scansioniFinte(int n) => [
    for (var i = 0; i < n; i++)
      XFile((File(p.join(tempDir.path, 'scan_$i.jpg'))..writeAsBytesSync(_pngMinimo)).path),
  ];

  Future<GoRouter> pumpRiepilogo(WidgetTester tester, List<XFile> scansioni) async {
    final router = GoRouter(
      initialLocation: '/scansione',
      routes: [
        GoRoute(
          path: '/scansione',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/scansione/riepilogo', extra: scansioni),
                child: const Text('vai al riepilogo'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/scansione/riepilogo',
          builder: (context, state) => RiepilogoPage(scansioni: state.extra! as List<XFile>),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const Scaffold(body: Center(child: Text('Dashboard'))),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(theme: AppTheme.dark, routerConfig: router));
    await tester.tap(find.text('vai al riepilogo'));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('mostra una riga per Scansione con chip "In sospeso"', (tester) async {
    await pumpRiepilogo(tester, scansioniFinte(2));

    expect(find.text('2 scansioni pronte per il riconoscimento AI'), findsOneWidget);
    expect(find.text('Scansione 1'), findsOneWidget);
    expect(find.text('Scansione 2'), findsOneWidget);
    expect(find.text('In sospeso'), findsNWidgets(2));
  });

  testWidgets('"Aggiungi altre" torna allo scanner (batch preservato)', (tester) async {
    await pumpRiepilogo(tester, scansioniFinte(1));

    await tester.tap(find.text('Aggiungi altre'));
    await tester.pumpAndSettle();

    expect(find.text('vai al riepilogo'), findsOneWidget);
    expect(find.text('Riepilogo batch'), findsNothing);
  });

  testWidgets('"Fine" naviga davvero a /dashboard', (tester) async {
    await pumpRiepilogo(tester, scansioniFinte(1));

    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Riepilogo batch'), findsNothing);
  });
}
