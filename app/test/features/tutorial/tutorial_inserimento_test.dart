import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/features/tutorial/application/tutorial_inserimento.dart';

import '../../core/auth/fake_auth_gateway.dart';

void main() {
  late PreferencesInMemoria preferences;

  ProviderContainer avvia() {
    final container = ProviderContainer(
      overrides: [accountPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    return container;
  }

  FaseTutorialInserimento fase(ProviderContainer c) =>
      c.read(tutorialInserimentoProvider).fase;

  setUp(() => preferences = PreferencesInMemoria());

  group('regola per gli utenti esistenti', () {
    test('utente nuovo: il primo momento è da mostrare', () async {
      await TutorialInserimentoController.allAvvio(preferences);

      expect(
        avvia().read(tutorialInserimentoProvider).mostraPrimoMomento,
        isTrue,
      );
    });

    test("dispositivo già entrato nell'app: visto senza mostrarlo", () async {
      await preferences.setString('account.benvenutoSuperato', 'true');

      await TutorialInserimentoController.allAvvio(preferences);

      expect(fase(avvia()), FaseTutorialInserimento.visto);
    });

    test('gira una volta sola: non riattiva un tutorial già deciso', () async {
      await TutorialInserimentoController.allAvvio(preferences);
      await preferences.setString('account.benvenutoSuperato', 'true');

      await TutorialInserimentoController.allAvvio(preferences);

      expect(fase(avvia()), FaseTutorialInserimento.daMostrare);
    });

    test(
      'la riapertura da Impostazioni non viene annullata al riavvio',
      () async {
        await preferences.setString('account.benvenutoSuperato', 'true');
        await TutorialInserimentoController.allAvvio(preferences);
        await avvia().read(tutorialInserimentoProvider.notifier).riapri();

        await TutorialInserimentoController.allAvvio(preferences);

        expect(fase(avvia()), FaseTutorialInserimento.daMostrare);
      },
    );

    test("senza la regola all'avvio non parte nessun tutorial", () {
      expect(fase(avvia()), FaseTutorialInserimento.visto);
    });
  });

  group('primo momento', () {
    setUp(() => TutorialInserimentoController.allAvvio(preferences));

    test('appena compare conta come visto: interrotto non riparte', () async {
      await avvia()
          .read(tutorialInserimentoProvider.notifier)
          .avviaPrimoMomento();

      expect(fase(avvia()), FaseTutorialInserimento.visto);
    });

    test("l'ultimo Avanti arma il secondo momento", () async {
      final c = avvia();
      await c.read(tutorialInserimentoProvider.notifier).avviaPrimoMomento();
      await c.read(tutorialInserimentoProvider.notifier).completaPrimoMomento();

      final stato = avvia().read(tutorialInserimentoProvider);
      expect(stato.fase, FaseTutorialInserimento.inAttesaPrimaScansione);
      expect(stato.mostraTappaRiepilogo, isTrue);
      expect(stato.mostraTappaCorrispondenza, isTrue);
    });
  });

  group('secondo momento', () {
    late ProviderContainer c;
    TutorialInserimentoController controller() =>
        c.read(tutorialInserimentoProvider.notifier);

    setUp(() async {
      await TutorialInserimentoController.allAvvio(preferences);
      c = avvia();
      await controller().avviaPrimoMomento();
      await controller().completaPrimoMomento();
    });

    test(
      'la tappa Riepilogo compare una volta e il tutorial resta in attesa',
      () async {
        await controller().avviaTappaRiepilogo();

        final stato = avvia().read(tutorialInserimentoProvider);
        expect(stato.mostraTappaRiepilogo, isFalse);
        expect(stato.mostraTappaCorrispondenza, isTrue);
      },
    );

    test('la tappa "Possibile corrispondenza" chiude il tutorial anche senza '
        'la tappa Riepilogo', () async {
      await controller().avviaTappaCorrispondenza();

      final stato = avvia().read(tutorialInserimentoProvider);
      expect(stato.fase, FaseTutorialInserimento.visto);
      expect(stato.mostraTappaRiepilogo, isFalse);
    });

    test('Salta chiude tutto', () async {
      await controller().salta();

      expect(fase(avvia()), FaseTutorialInserimento.visto);
    });
  });

  test('la riapertura riarma entrambi i momenti', () async {
    await TutorialInserimentoController.allAvvio(preferences);
    final c = avvia();
    final controller = c.read(tutorialInserimentoProvider.notifier);
    await controller.avviaPrimoMomento();
    await controller.completaPrimoMomento();
    await controller.avviaTappaRiepilogo();
    await controller.avviaTappaCorrispondenza();

    await controller.riapri();

    final stato = avvia().read(tutorialInserimentoProvider);
    expect(stato.mostraPrimoMomento, isTrue);
    expect(stato.tappaRiepilogoMostrata, isFalse);
  });
}
