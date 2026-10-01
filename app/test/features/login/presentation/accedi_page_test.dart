import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/features/login/presentation/accedi_page.dart';

import '../../../core/auth/fake_auth_gateway.dart';

void main() {
  late FakeAuthGateway gateway;

  setUp(() => gateway = FakeAuthGateway());

  Future<ProviderContainer> mostra(
    WidgetTester tester, {
    required ModoAccesso modo,
  }) async {
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        accountPreferencesProvider.overrideWithValue(PreferencesInMemoria()),
        haDatiLocaliProvider.overrideWithValue(() async => false),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: AccediPage(modo: modo)),
      ),
    );
    return container;
  }

  Future<void> compilaEInvia(
    WidgetTester tester,
    String pulsante,
  ) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'mario@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'segreta123',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, pulsante));
    await tester.tap(find.widgetWithText(FilledButton, pulsante));
    await tester.pumpAndSettle();
  }

  testWidgets('registrarsi con email mette l\'email in attesa di conferma', (
    tester,
  ) async {
    final container = await mostra(tester, modo: ModoAccesso.registrati);
    expect(find.text('Crea il tuo account'), findsOneWidget);

    await compilaEInvia(tester, 'Crea account');

    expect(
      container.read(sessionControllerProvider).emailInAttesa,
      'mario@example.com',
    );
    expect(
      find.text('Link di conferma inviato a mario@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('si passa da "Crea account" ad "Accedi" e un accesso con '
      'credenziali errate mostra l\'errore', (tester) async {
    await mostra(tester, modo: ModoAccesso.registrati);

    await tester.tap(find.text('Ho già un account'));
    await tester.pumpAndSettle();
    await compilaEInvia(tester, 'Accedi');

    expect(find.text('Email o password non corrette.'), findsOneWidget);
  });

  testWidgets('accedere con Google autentica', (tester) async {
    final container = await mostra(tester, modo: ModoAccesso.accedi);

    await tester.tap(find.text('Continua con Google'));
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).profilo?.metodo,
      MetodoAccesso.google,
    );
  });
}
