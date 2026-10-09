import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';

import 'fake_auth_gateway.dart';

void main() {
  late FakeAuthGateway gateway;
  late PreferencesInMemoria preferences;
  late bool datiLocali;

  ProviderContainer avvia() {
    final container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        accountPreferencesProvider.overrideWithValue(preferences),
        haDatiLocaliProvider.overrideWithValue(() async => datiLocali),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    gateway = FakeAuthGateway();
    preferences = PreferencesInMemoria();
    datiLocali = false;
  });

  test('al primo avvio si atterra sul benvenuto', () {
    final sessione = avvia().read(sessionControllerProvider);

    expect(sessione.ingresso, Ingresso.benvenuto);
    expect(sessione.profilo, isNull);
  });
  test('"Usa senza account" porta in Modalità locale e vale anche ai '
      'riavvii successivi', () async {
    await avvia()
        .read(sessionControllerProvider.notifier)
        .continuaSenzaAccount();

    final dopoRiavvio = avvia().read(sessionControllerProvider);

    expect(dopoRiavvio.ingresso, Ingresso.app);
    expect(dopoRiavvio.profilo, isNull);
  });
  test("login senza dati locali: entra nell'app e la Modalità locale si "
      "esaurisce, quindi dopo il logout resta solo l'accesso", () async {
    final container = avvia();
    final controller = container.read(sessionControllerProvider.notifier);

    await controller.accediConApple();
    await pumpEventQueue();

    final dentro = container.read(sessionControllerProvider);
    expect(dentro.ingresso, Ingresso.app);
    expect(dentro.profilo?.metodo, MetodoAccesso.apple);

    await controller.esci();
    await pumpEventQueue();

    expect(
      container.read(sessionControllerProvider).ingresso,
      Ingresso.soloAccesso,
    );
    expect(
      avvia().read(sessionControllerProvider).ingresso,
      Ingresso.soloAccesso,
    );
  });
  test('login con dati locali dal benvenuto: la Modalità locale resta in '
      "sospeso per l'importazione, e uscendo si torna lì", () async {
    datiLocali = true;
    final container = avvia();
    final controller = container.read(sessionControllerProvider.notifier);

    await controller.accediConGoogle();
    await pumpEventQueue();

    final dentro = container.read(sessionControllerProvider);
    expect(dentro.profilo?.metodo, MetodoAccesso.google);
    expect(dentro.importazioneInSospeso, isTrue);

    await controller.esci();
    await pumpEventQueue();

    final fuori = avvia().read(sessionControllerProvider);
    expect(fuori.ingresso, Ingresso.app);
    expect(fuori.profilo, isNull);
  });

  test("una sessione salvata viene ripristinata all'avvio", () {
    gateway = FakeAuthGateway(
      sessioneSalvata: const Profilo(
        email: 'mario@example.com',
        metodo: MetodoAccesso.email,
      ),
    );

    final sessione = avvia().read(sessionControllerProvider);

    expect(sessione.ingresso, Ingresso.app);
    expect(sessione.profilo?.email, 'mario@example.com');
  });
  group('Profilo autenticato offline (#170, variante A)', () {
    const salvato = Profilo(
      email: 'mario@example.com',
      metodo: MetodoAccesso.email,
    );

    test("sessione salvata senza rete: blocco offline, e Riprova con la rete "
        "tornata riporta nell'app", () async {
      gateway = FakeAuthGateway(sessioneSalvata: salvato)..online = false;
      final container = avvia();
      container.read(sessionControllerProvider);
      await pumpEventQueue();

      expect(
        container.read(sessionControllerProvider).ingresso,
        Ingresso.offline,
      );

      gateway.online = true;
      await container
          .read(sessionControllerProvider.notifier)
          .riprovaConnessione();

      expect(container.read(sessionControllerProvider).ingresso, Ingresso.app);
    });

    test('la Modalità locale non si blocca mai offline', () async {
      gateway.online = false;
      final container = avvia();
      await container
          .read(sessionControllerProvider.notifier)
          .continuaSenzaAccount();
      await pumpEventQueue();

      expect(container.read(sessionControllerProvider).ingresso, Ingresso.app);
    });

    test('uscendo dal blocco offline con il logout si torna al benvenuto '
        'giusto', () async {
      gateway = FakeAuthGateway(sessioneSalvata: salvato)..online = false;
      final container = avvia();
      container.read(sessionControllerProvider);
      await pumpEventQueue();

      await container.read(sessionControllerProvider.notifier).esci();
      await pumpEventQueue();

      expect(
        container.read(sessionControllerProvider).ingresso,
        isNot(Ingresso.offline),
      );
    });
  });

  group('registrazione con email', () {
    test("dal benvenuto si entra in Modalità locale con l'email in attesa, "
        'anche dopo un riavvio', () async {
      await avvia()
          .read(sessionControllerProvider.notifier)
          .registratiConEmail('mario@example.com', 'segreta123');

      final dopoRiavvio = avvia().read(sessionControllerProvider);
      expect(dopoRiavvio.ingresso, Ingresso.app);
      expect(dopoRiavvio.profilo, isNull);
      expect(dopoRiavvio.emailInAttesa, 'mario@example.com');
    });

    test(
      "accedere prima di confermare segnala l'email non confermata",
      () async {
        final controller = avvia().read(sessionControllerProvider.notifier);
        await controller.registratiConEmail('mario@example.com', 'segreta123');

        await expectLater(
          controller.accediConEmail('mario@example.com', 'segreta123'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.errore,
              'errore',
              AuthErrore.emailNonConfermata,
            ),
          ),
        );
      },
    );

    test("il link di conferma autentica e toglie l'attesa", () async {
      final container = avvia();
      await container
          .read(sessionControllerProvider.notifier)
          .registratiConEmail('mario@example.com', 'segreta123');

      gateway.confermaEmailDaLink('mario@example.com');
      await pumpEventQueue();

      final sessione = container.read(sessionControllerProvider);
      expect(sessione.profilo?.email, 'mario@example.com');
      expect(sessione.emailInAttesa, isNull);
      expect(avvia().read(sessionControllerProvider).emailInAttesa, isNull);
    });

    test('"Cambia email" annulla l\'attesa', () async {
      final container = avvia();
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.registratiConEmail('mario@example.com', 'segreta123');

      await controller.annullaEmailInAttesa();

      expect(container.read(sessionControllerProvider).emailInAttesa, isNull);
    });

    test('"Reinvia" chiede un nuovo link per l\'email in attesa', () async {
      final controller = avvia().read(sessionControllerProvider.notifier);
      await controller.registratiConEmail('mario@example.com', 'segreta123');

      await controller.reinviaConferma();

      expect(gateway.confermeInviate, 2);
    });
  });

  group('eliminazione account', () {
    test(
      "riporta al benvenuto solo accesso e l'account non esiste più",
      () async {
        final container = avvia();
        final controller = container.read(sessionControllerProvider.notifier);
        await controller.accediConGoogle();
        await pumpEventQueue();

        await controller.eliminaAccount();
        await pumpEventQueue();

        final sessione = container.read(sessionControllerProvider);
        expect(sessione.profilo, isNull);
        expect(sessione.ingresso, Ingresso.soloAccesso);
        expect(gateway.accountEliminati, ['mario.rossi@gmail.com']);
      },
    );

    test('se fallisce il Profilo resta autenticato', () async {
      final container = avvia();
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.accediConGoogle();
      await pumpEventQueue();
      gateway.prossimoErrore = const AuthException(AuthErrore.rete);

      await expectLater(
        controller.eliminaAccount(),
        throwsA(isA<AuthException>()),
      );

      expect(container.read(sessionControllerProvider).profilo, isNotNull);
    });
  });
}
