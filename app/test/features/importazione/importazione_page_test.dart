import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/data/supabase/importazione_modalita_locale.dart';
import 'package:mycomicbrain/features/importazione/application/importazione_controller.dart';
import 'package:mycomicbrain/features/importazione/presentation/importazione_page.dart';

import '../../core/auth/fake_auth_gateway.dart';

/// Un importatore in memoria: ricorda gli id usati e può fallire a comando.
class FakeImportatore implements ImportatoreModalitaLocale {
  RiepilogoModalitaLocale riepilogoDaRestituire = const RiepilogoModalitaLocale(
    fumetti: 12,
    scansioniDaCompletare: 3,
    fumettiNellAccount: 0,
  );
  bool fallisci = false;
  bool scartati = false;
  final importId = <String>[];
  Completer<void>? inPausa;

  @override
  Future<RiepilogoModalitaLocale> riepilogo() async => riepilogoDaRestituire;

  @override
  Future<EsitoImportazione> importa(
    String importId, {
    void Function(AvanzamentoImportazione)? avanzamento,
  }) async {
    this.importId.add(importId);
    avanzamento?.call(
      const AvanzamentoImportazione(FaseImportazione.cover, 1, 4),
    );
    await inPausa?.future;
    if (fallisci) throw Exception('rete');
    return EsitoImportazione(
      fumettiNellAccount:
          riepilogoDaRestituire.fumettiNellAccount +
          riepilogoDaRestituire.fumetti,
    );
  }

  @override
  Future<void> scartaDatiLocali() async => scartati = true;
}

void main() {
  late FakeAuthGateway gateway;
  late PreferencesInMemoria preferences;
  late FakeImportatore importatore;
  late ProviderContainer container;

  setUp(() async {
    gateway = FakeAuthGateway(
      sessioneSalvata: const Profilo(
        email: 'mario@example.com',
        metodo: MetodoAccesso.email,
      ),
    );
    // Chi ha una sessione salvata ha già superato il benvenuto.
    preferences = PreferencesInMemoria();
    await preferences.setString('account.benvenutoSuperato', 'true');
    importatore = FakeImportatore();
    container = ProviderContainer(
      overrides: [
        authGatewayProvider.overrideWithValue(gateway),
        accountPreferencesProvider.overrideWithValue(preferences),
        haDatiLocaliProvider.overrideWithValue(
          () async => !importatore.scartati,
        ),
        importatoreModalitaLocaleProvider.overrideWithValue(importatore),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> mostra(WidgetTester tester) async {
    container.read(sessionControllerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ImportazionePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Ingresso ingresso() => container.read(sessionControllerProvider).ingresso;

  testWidgets('account nuovo: il prompt conta fumetti e scansioni e invita '
      'a importarli', (tester) async {
    await mostra(tester);

    expect(
      find.text(
        'Abbiamo trovato 12 fumetti e 3 scansioni da completare su questo '
        'dispositivo',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Importali nel tuo account per ritrovarli su ogni dispositivo.',
      ),
      findsOneWidget,
    );
    expect(
      find.text("La conversazione con l'Assistente non viene importata."),
      findsOneWidget,
    );
  });

  testWidgets('account esistente: avvisa che i fumetti si aggiungono alla '
      'stessa collezione', (tester) async {
    importatore.riepilogoDaRestituire = const RiepilogoModalitaLocale(
      fumetti: 1,
      scansioniDaCompletare: 0,
      fumettiNellAccount: 214,
    );
    await mostra(tester);

    expect(
      find.text('Abbiamo trovato 1 fumetto su questo dispositivo'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Il tuo account ha già 214 fumetti. Quelli di questo dispositivo '
        'verranno aggiunti alla stessa collezione.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('importazione riuscita: "Fatto!" e solo da "Vai alla '
      "collezione\" la Modalità locale si esaurisce", (tester) async {
    await mostra(tester);

    await tester.tap(find.text('Importa nel mio account'));
    await tester.pumpAndSettle();

    expect(find.text('Fatto!'), findsOneWidget);
    expect(
      find.text('La collezione ora è nel tuo account: 12 fumetti in totale.'),
      findsOneWidget,
    );
    expect(ingresso(), Ingresso.importazione);

    await tester.tap(find.text('Vai alla collezione'));
    await tester.pumpAndSettle();

    expect(ingresso(), Ingresso.app);
  });

  testWidgets("durante l'importazione la schermata mostra l'avanzamento", (
    tester,
  ) async {
    importatore.inPausa = Completer();
    await mostra(tester);

    await tester.tap(find.text('Importa nel mio account'));
    await tester.pump();

    expect(find.text('Importazione in corso…'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(
      find.text(
        "Se l'app si chiude, l'importazione riprende alla prossima apertura.",
      ),
      findsOneWidget,
    );

    importatore.inPausa!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('un errore permette di riprovare con lo stesso id, senza '
      'esaurire la Modalità locale', (tester) async {
    importatore.fallisci = true;
    await mostra(tester);

    await tester.tap(find.text('Importa nel mio account'));
    await tester.pumpAndSettle();

    expect(find.text('Importazione interrotta'), findsOneWidget);
    expect(ingresso(), Ingresso.importazione);

    importatore.fallisci = false;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(find.text('Fatto!'), findsOneWidget);
    expect(importatore.importId, hasLength(2));
    expect(importatore.importId.toSet(), hasLength(1));
  });

  testWidgets('"Esci e riprova più tardi" fa logout lasciando i dati '
      'locali, e al prossimo accesso riprende con lo stesso id', (
    tester,
  ) async {
    importatore.fallisci = true;
    await mostra(tester);
    await tester.tap(find.text('Importa nel mio account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Esci e riprova più tardi'));
    await tester.pumpAndSettle();

    expect(container.read(sessionControllerProvider).profilo, isNull);
    expect(importatore.scartati, isFalse);
    expect(ingresso(), Ingresso.app);

    await container.read(sessionControllerProvider.notifier).accediConApple();
    container.invalidate(importazioneControllerProvider);
    await tester.pumpAndSettle();

    expect(find.text("L'importazione non è finita"), findsOneWidget);
    importatore.fallisci = false;
    await tester.tap(find.text("Riprendi l'importazione"));
    await tester.pumpAndSettle();

    expect(importatore.importId.toSet(), hasLength(1));
  });

  testWidgets('"Non importare" chiede una seconda conferma prima di '
      'scartare i dati locali', (tester) async {
    await mostra(tester);

    await tester.tap(find.text('Non importare'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminare i dati locali?'), findsOneWidget);

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(importatore.scartati, isFalse);
    expect(ingresso(), Ingresso.importazione);

    await tester.tap(find.text('Non importare'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elimina dati locali'));
    await tester.pumpAndSettle();

    expect(importatore.scartati, isTrue);
    expect(importatore.importId, isEmpty);
    expect(ingresso(), Ingresso.app);
  });
}
