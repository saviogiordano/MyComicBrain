import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/features/login/presentation/avviso_accesso.dart';

import '../../../core/auth/fake_auth_gateway.dart';

void main() {
  late FakeAuthGateway gateway;
  late int ritorniInDashboard;

  setUp(() {
    gateway = FakeAuthGateway();
    ritorniInDashboard = 0;
  });

  Future<ProviderContainer> mostra(WidgetTester tester) async {
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
        child: MaterialApp(
          builder: (context, child) => AvvisoAccesso(
            vaiAllaDashboard: () => ritorniInDashboard++,
            child: child!,
          ),
          home: const Scaffold(),
        ),
      ),
    );
    return container;
  }

  testWidgets('un accesso riporta alla Dashboard e lo conferma', (
    tester,
  ) async {
    final container = await mostra(tester);

    await container.read(sessionControllerProvider.notifier).accediConGoogle();
    await tester.pumpAndSettle();

    expect(ritorniInDashboard, 1);
    expect(find.textContaining('Accesso effettuato'), findsOneWidget);
  });

  testWidgets('anche la conferma email dal link conta come accesso', (
    tester,
  ) async {
    final container = await mostra(tester);
    await container
        .read(sessionControllerProvider.notifier)
        .registratiConEmail('mario@example.com', 'Segreta123');
    await tester.pumpAndSettle();

    gateway.confermaEmailDaLink('mario@example.com');
    await tester.pumpAndSettle();

    expect(ritorniInDashboard, 1);
    expect(
      find.text('Accesso effettuato come mario@example.com'),
      findsOneWidget,
    );
  });

  testWidgets("una sessione ripristinata all'avvio non mostra nulla", (
    tester,
  ) async {
    gateway = FakeAuthGateway(
      sessioneSalvata: const Profilo(
        email: 'mario@example.com',
        metodo: MetodoAccesso.email,
      ),
    );
    await mostra(tester);
    await tester.pumpAndSettle();

    expect(ritorniInDashboard, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets("il logout non mostra l'avviso", (tester) async {
    final container = await mostra(tester);
    final controller = container.read(sessionControllerProvider.notifier);
    await controller.accediConGoogle();
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    ritorniInDashboard = 0;

    await controller.esci();
    await tester.pumpAndSettle();

    expect(ritorniInDashboard, 0);
    expect(find.byType(SnackBar), findsNothing);
  });
}
