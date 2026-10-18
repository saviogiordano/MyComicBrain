import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/descrizione_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/sincronizzazione_providers.dart';
import 'package:mycomicbrain/features/sincronizzazione/presentation/stato_sincronizzazione.dart';

/// La sezione "Non accettate dal server" dello sheet e di Impostazioni ›
/// Sincronizzazione (#225).
void main() {
  late _Motore motore;
  late StreamController<List<ModificaRifiutata>> rifiutate;

  const maus = ModificaRifiutata(
    voce: 'v1',
    riga: (tabella: 'copie', id: 'c1'),
    tipo: TipoVoceRegistro.modifica,
    titolo: 'Maus',
    descrizione: 'Copia modificata: Maus',
    codice: '23514',
    messaggio: 'violazione del vincolo',
    versioneApp: '1.4.0+12',
  );

  setUp(() {
    motore = _Motore();
    rifiutate = StreamController();
  });

  tearDown(() => rifiutate.close());

  Future<void> mostra(
    WidgetTester tester, {
    FaseSincronizzazione fase = FaseSincronizzazione.sincronizzata,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statoSincronizzazioneProvider.overrideWith(
            (ref) => Stream.value(
              StatoSincronizzazione(fase: fase, replicaScaricata: true),
            ),
          ),
          motoreSincronizzazioneProvider.overrideWithValue(motore),
          modificheInSospesoProvider.overrideWith((ref) => Stream.value(1)),
          elencoModificheProvider.overrideWith(
            (ref) => Stream.value(const ['Copia modificata: Maus']),
          ),
          modificheRifiutateProvider.overrideWith((ref) => rifiutate.stream),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: SingleChildScrollView(child: DettaglioSincronizzazione()),
          ),
        ),
      ),
    );
    rifiutate.add(const [maus]);
    await tester.pumpAndSettle();
  }

  testWidgets('in cima, con la pillola "da controllare"', (tester) async {
    await mostra(tester);

    expect(find.text('Non accettate dal server'), findsOneWidget);
    expect(find.text('1 da controllare'), findsOneWidget);
    final sezione = tester.getTopLeft(find.text('Non accettate dal server'));
    final stato = tester.getTopLeft(find.text('Stato'));
    expect(sezione.dy, lessThan(stato.dy));
  });

  testWidgets("senza rifiuti la sezione non c'è", (tester) async {
    await mostra(tester);
    rifiutate.add(const []);
    // Senza rifiuti la riga in sospeso fa girare l'icona: niente settle.
    await tester.pump();
    await tester.pump();

    expect(find.text('Non accettate dal server'), findsNothing);
  });

  testWidgets('Riprova rimette la voce nel push', (tester) async {
    await mostra(tester);

    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(motore.riprovate, ['v1']);
  });

  testWidgets('Scarta chiede conferma con il titolo', (tester) async {
    await mostra(tester);

    await tester.tap(find.text('Scarta'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Le modifiche a «Maus» fatte su questo telefono andranno perse.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(motore.righeScartate, isEmpty);

    await tester.tap(find.text('Scarta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scarta le modifiche'));
    await tester.pumpAndSettle();
    expect(motore.righeScartate, [maus.riga]);
  });

  testWidgets('Scarta non riuscito lo dice sulla voce', (tester) async {
    motore.erroreScarta = Exception('rete');
    await mostra(tester);

    await tester.tap(find.text('Scarta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scarta le modifiche'));
    await tester.pumpAndSettle();

    expect(
      find.text('Non è stato possibile scartare. Riprova più tardi.'),
      findsOneWidget,
    );
  });

  testWidgets('offline Scarta è disabilitato', (tester) async {
    await mostra(tester, fase: FaseSincronizzazione.offline);

    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Scarta'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Copia dettagli mette i dettagli negli appunti', (tester) async {
    String? copiato;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiato = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await mostra(tester);

    await tester.tap(find.text('Copia dettagli'));
    await tester.pumpAndSettle();

    expect(copiato, maus.dettagli);
    expect(find.text('Copiati'), findsOneWidget);
  });
}

class _Motore implements MotoreSincronizzazione {
  final riprovate = <String>[];
  final righeScartate = <RigaReplicata>[];
  Exception? erroreScarta;

  @override
  Future<void> riprova(String voce) async => riprovate.add(voce);

  @override
  Future<void> scarta(RigaReplicata riga) async {
    if (erroreScarta case final errore?) throw errore;
    righeScartate.add(riga);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
