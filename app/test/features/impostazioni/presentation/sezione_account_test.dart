import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/features/impostazioni/presentation/sezione_account.dart';

import '../../../core/auth/fake_auth_gateway.dart';

void main() {
  late FakeAuthGateway gateway;
  late PreferencesInMemoria preferences;

  setUp(() {
    gateway = FakeAuthGateway();
    preferences = PreferencesInMemoria()
      ..valori['account.benvenutoSuperato'] = 'true';
  });

  Future<ProviderContainer> mostra(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        accountPreferencesProvider.overrideWithValue(preferences),
        haDatiLocaliProvider.overrideWithValue(() async => false),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: SezioneAccount())),
        ),
      ),
    );
    return container;
  }

  testWidgets('in Modalità locale invita a creare un account', (tester) async {
    await mostra(tester);

    expect(find.text('Modalità locale'), findsOneWidget);
    expect(find.text('Crea account o accedi'), findsOneWidget);
  });

  testWidgets("con l'email in attesa offre Reinvia e Cambia email", (
    tester,
  ) async {
    gateway.account['mario@example.com'] = (
      password: 'segreta123',
      confermato: false,
    );
    preferences.valori['account.emailInAttesa'] = 'mario@example.com';
    final container = await mostra(tester);

    expect(find.text('Conferma la tua email'), findsOneWidget);
    expect(find.textContaining('mario@example.com'), findsOneWidget);

    await tester.tap(find.text('Reinvia'));
    await tester.pumpAndSettle();
    expect(gateway.confermeInviate, 1);

    await tester.tap(find.text('Cambia email'));
    await tester.pumpAndSettle();
    expect(container.read(sessionControllerProvider).emailInAttesa, isNull);
  });

  testWidgets('con un Profilo mostra chi è connesso e permette di uscire '
      'dopo conferma', (tester) async {
    gateway = FakeAuthGateway(
      sessioneSalvata: const Profilo(
        email: 'x7k2m9@privaterelay.appleid.com',
        metodo: MetodoAccesso.apple,
      ),
    );
    final container = await mostra(tester);

    expect(find.text('x7k2m9@privaterelay.appleid.com'), findsOneWidget);
    expect(find.text('Accesso con Apple'), findsOneWidget);

    await tester.tap(find.text('Esci'));
    await tester.pumpAndSettle();
    expect(find.text("Uscire dall'account?"), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Esci'));
    await tester.pumpAndSettle();
    expect(container.read(sessionControllerProvider).profilo, isNull);
  });
}
