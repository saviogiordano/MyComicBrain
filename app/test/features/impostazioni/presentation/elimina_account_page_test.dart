import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/features/impostazioni/presentation/elimina_account_page.dart';

import '../../../core/auth/fake_auth_gateway.dart';

void main() {
  late FakeAuthGateway gateway;

  Future<ProviderContainer> mostra(
    WidgetTester tester, {
    MetodoAccesso metodo = MetodoAccesso.email,
  }) async {
    gateway = FakeAuthGateway(
      sessioneSalvata: Profilo(email: 'mario@example.com', metodo: metodo),
    );
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        accountPreferencesProvider.overrideWithValue(
          PreferencesInMemoria()..valori['account.benvenutoSuperato'] = 'true',
        ),
        haDatiLocaliProvider.overrideWithValue(() async => false),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const Scaffold(body: Text('Dashboard')),
        ),
        GoRoute(
          path: '/account/elimina',
          builder: (context, state) => const EliminaAccountPage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    unawaited(router.push('/account/elimina'));
    await tester.pumpAndSettle();
    return container;
  }

  FilledButton pulsante(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Elimina definitivamente'),
  );

  testWidgets('elenca le conseguenze e attiva il pulsante solo dopo la '
      'spunta', (tester) async {
    await mostra(tester);

    expect(find.textContaining('mario@example.com'), findsOneWidget);
    expect(find.textContaining('non si può annullare'), findsOneWidget);
    expect(find.textContaining('Apple'), findsNothing);
    expect(pulsante(tester).onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(pulsante(tester).onPressed, isNotNull);
  });

  testWidgets("con Apple avvisa che l'accesso verrà revocato", (tester) async {
    await mostra(tester, metodo: MetodoAccesso.apple);

    expect(
      find.text("Revocheremo anche l'accesso con Apple."),
      findsOneWidget,
    );
  });

  // La Modalità locale non è esaurita (dati non importati): il router non
  // porta al benvenuto, è la schermata a dover tornare alla Dashboard.
  testWidgets("elimina l'account, lo conferma e torna alla Dashboard", (
    tester,
  ) async {
    final container = await mostra(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Elimina definitivamente'));
    await tester.pumpAndSettle();

    expect(gateway.accountEliminati, ['mario@example.com']);
    expect(container.read(sessionControllerProvider).profilo, isNull);
    expect(find.text('Account eliminato'), findsOneWidget);
    expect(find.byType(EliminaAccountPage), findsNothing);
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets("senza rete mostra l'errore e permette di riprovare", (
    tester,
  ) async {
    final container = await mostra(tester);
    gateway.prossimoErrore = const AuthException(AuthErrore.rete);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Elimina definitivamente'));
    await tester.pumpAndSettle();

    expect(find.text('Serve una connessione a Internet.'), findsOneWidget);
    expect(container.read(sessionControllerProvider).profilo, isNotNull);
    expect(pulsante(tester).onPressed, isNotNull);
  });

  testWidgets('se il foglio Apple viene chiuso non mostra errori', (
    tester,
  ) async {
    await mostra(tester, metodo: MetodoAccesso.apple);
    gateway.prossimoErrore = const AuthException(AuthErrore.annullato);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Elimina definitivamente'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(gateway.accountEliminati, isEmpty);
  });
}
