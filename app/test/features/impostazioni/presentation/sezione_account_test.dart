import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/sincronizzatore.dart';
import 'package:mycomicbrain/features/impostazioni/presentation/sezione_account.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/sincronizzazione_providers.dart';

import '../../../core/auth/fake_auth_gateway.dart';

void main() {
  late FakeAuthGateway gateway;
  late PreferencesInMemoria preferences;

  setUp(() {
    gateway = FakeAuthGateway();
    preferences = PreferencesInMemoria()
      ..valori['account.benvenutoSuperato'] = 'true';
  });

  Future<ProviderContainer> mostra(
    WidgetTester tester, {
    List<Override> sincronizzazione = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        accountPreferencesProvider.overrideWithValue(preferences),
        haDatiLocaliProvider.overrideWithValue(() async => false),
        ...sincronizzazione,
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

  testWidgets('con un Profilo offre "Elimina account"', (tester) async {
    gateway = FakeAuthGateway(
      sessioneSalvata: const Profilo(
        email: 'mario@example.com',
        metodo: MetodoAccesso.email,
      ),
    );
    await mostra(tester);

    expect(find.text('Elimina account'), findsOneWidget);
  });

  group('logout con Modifiche in sospeso (#217, prototipo #201)', () {
    late _Motore motore;

    setUp(() {
      gateway = FakeAuthGateway(
        sessioneSalvata: const Profilo(
          email: 'mario@example.com',
          metodo: MetodoAccesso.email,
        ),
      );
      motore = _Motore();
    });

    List<Override> sincronizzazione({bool offline = false}) => [
      modificheInSospesoProvider.overrideWith((ref) => Stream.value(3)),
      scansioniInAttesaProvider.overrideWith(
        (ref) => Stream.value({'scansione.jpg'}),
      ),
      statoSincronizzazioneProvider.overrideWith(
        (ref) => Stream.value(
          StatoSincronizzazione(
            fase: offline
                ? FaseSincronizzazione.offline
                : FaseSincronizzazione.sincronizzata,
            replicaScaricata: true,
          ),
        ),
      ),
      motoreSincronizzazioneProvider.overrideWithValue(motore),
      replicaDelProfiloProvider.overrideWithValue(null),
    ];

    Future<void> apriLogout(WidgetTester tester) async {
      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
    }

    testWidgets('"Esci comunque" chiede una seconda conferma e poi esce', (
      tester,
    ) async {
      final container = await mostra(
        tester,
        sincronizzazione: sincronizzazione(),
      );
      await tester.pumpAndSettle();
      await apriLogout(tester);

      expect(find.text('Modifiche non sincronizzate'), findsOneWidget);
      expect(
        find.textContaining('3 modifiche non sono ancora state sincronizzate'),
        findsOneWidget,
      );

      await tester.tap(find.text('Esci comunque'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminare 3 modifiche?'), findsOneWidget);
      expect(
        find.textContaining('Anche le scansioni in attesa di rete'),
        findsOneWidget,
      );

      await tester.tap(find.text('Esci e perdi le modifiche'));
      await tester.pumpAndSettle();
      expect(container.read(sessionControllerProvider).profilo, isNull);
    });

    testWidgets('"Sincronizza e esci" esce solo se la sincronizzazione '
        'riesce', (tester) async {
      final container = await mostra(
        tester,
        sincronizzazione: sincronizzazione(),
      );
      await tester.pumpAndSettle();
      await apriLogout(tester);

      motore.esito = SincronizzazioneFallita(
        StateError('server'),
        offline: false,
      );
      await tester.tap(find.text('Sincronizza e esci'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'La sincronizzazione non è riuscita. Le modifiche sono ancora su '
          'questo telefono.',
        ),
        findsOneWidget,
      );
      expect(container.read(sessionControllerProvider).profilo, isNotNull);

      motore.esito = const SincronizzazioneRiuscita(
        EsitoCiclo(inviate: 3, ricevute: 0, scartate: []),
      );
      await tester.tap(find.text('Sincronizza e esci'));
      await tester.pumpAndSettle();
      expect(motore.chiamate, 2);
      expect(container.read(sessionControllerProvider).profilo, isNull);
    });

    testWidgets('offline "Sincronizza e esci" è disabilitato', (tester) async {
      await mostra(tester, sincronizzazione: sincronizzazione(offline: true));
      await tester.pumpAndSettle();
      await apriLogout(tester);

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Sincronizza e esci'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.text('Sei offline: collegati per sincronizzare.'),
        findsOneWidget,
      );
    });

    testWidgets('senza Modifiche in sospeso resta il dialog semplice', (
      tester,
    ) async {
      await mostra(
        tester,
        sincronizzazione: [
          modificheInSospesoProvider.overrideWith((ref) => Stream.value(0)),
        ],
      );
      await tester.pumpAndSettle();
      await apriLogout(tester);

      expect(find.text("Uscire dall'account?"), findsOneWidget);
      expect(find.text('Modifiche non sincronizzate'), findsNothing);
    });
  });
}

class _Motore implements MotoreSincronizzazione {
  EsitoSincronizzazione esito = const SincronizzazioneRiuscita(
    EsitoCiclo(inviate: 0, ricevute: 0, scartate: []),
  );
  int chiamate = 0;

  @override
  Future<EsitoSincronizzazione> sincronizzaOra() async {
    chiamate++;
    return esito;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
