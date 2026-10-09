import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/features/login/presentation/offline_page.dart';

import '../../../core/auth/fake_auth_gateway.dart';

void main() {
  testWidgets('spiega che serve la rete e "Riprova", con la rete tornata, '
      "riporta nell'app", (tester) async {
    final gateway = FakeAuthGateway(
      sessioneSalvata: const Profilo(
        email: 'mario@example.com',
        metodo: MetodoAccesso.email,
      ),
    )..online = false;
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        accountPreferencesProvider.overrideWithValue(PreferencesInMemoria()),
        haDatiLocaliProvider.overrideWithValue(() async => false),
      ],
    );
    addTearDown(container.dispose);
    // Nell'app la sessione la costruisce subito il router.
    container.read(sessionControllerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OfflinePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sei offline'), findsOneWidget);
    expect(
      container.read(sessionControllerProvider).ingresso,
      Ingresso.offline,
    );

    gateway.online = true;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(container.read(sessionControllerProvider).ingresso, Ingresso.app);
  });
}
