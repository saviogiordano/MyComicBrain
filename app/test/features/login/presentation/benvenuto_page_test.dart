import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/features/login/presentation/benvenuto_page.dart';

import '../../../core/auth/fake_auth_gateway.dart';

void main() {
  late PreferencesInMemoria preferences;

  setUp(() => preferences = PreferencesInMemoria());

  Future<ProviderContainer> mostra(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(FakeAuthGateway()),
        accountPreferencesProvider.overrideWithValue(preferences),
        haDatiLocaliProvider.overrideWithValue(() async => false),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BenvenutoPage()),
      ),
    );
    return container;
  }

  testWidgets('al primo avvio propone account in primo piano e "Usa senza '
      'account", che spiega la Modalità locale prima di confermare', (
    tester,
  ) async {
    final container = await mostra(tester);

    expect(find.text('Crea un account'), findsOneWidget);
    expect(find.text('Accedi'), findsOneWidget);

    await tester.tap(find.text('Usa senza account'));
    await tester.pumpAndSettle();
    expect(find.text("Usare l'app senza account?"), findsOneWidget);

    await tester.tap(find.text('Continua senza account'));
    await tester.pumpAndSettle();

    expect(
      container.read(sessionControllerProvider).ingresso,
      Ingresso.app,
    );
  });

  testWidgets('con la Modalità locale esaurita offre solo l\'accesso', (
    tester,
  ) async {
    preferences.valori['account.modalitaLocaleEsaurita'] = 'true';

    await mostra(tester);

    expect(find.text('Usa senza account'), findsNothing);
    expect(find.text('Continua con Apple'), findsOneWidget);
    expect(find.text('Continua con Google'), findsOneWidget);
    expect(find.text('Accedi con email'), findsOneWidget);
    expect(
      find.textContaining('la collezione è già passata a un account'),
      findsOneWidget,
    );
  });
}
