import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/sincronizzatore.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/sincronizzazione_providers.dart';
import 'package:mycomicbrain/features/sincronizzazione/presentation/primo_download_page.dart';

/// Il primo download e "Serve una connessione" (prototipo #201, punti 3 e
/// 4).
void main() {
  late StreamController<StatoSincronizzazione> stati;
  late _Motore motore;

  setUp(() {
    stati = StreamController();
    motore = _Motore();
  });

  tearDown(() => stati.close());

  Future<void> mostra(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statoSincronizzazioneProvider.overrideWith((ref) => stati.stream),
          motoreSincronizzazioneProvider.overrideWithValue(motore),
          dimensioniCollezioneProvider.overrideWith(
            (ref) async => (righe: 1000, fumetti: 162),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const PrimoDownloadPage(),
        ),
      ),
    );
  }

  testWidgets("scarica con l'avanzamento in fumetti", (tester) async {
    await mostra(tester);
    stati.add(
      const StatoSincronizzazione(
        fase: FaseSincronizzazione.inCorso,
        replicaScaricata: false,
        righeScaricate: 500,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Scarico la tua collezione'), findsOneWidget);
    expect(find.text('81 di 162 fumetti'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('senza rete: "Serve una connessione", e Riprova riparte', (
    tester,
  ) async {
    await mostra(tester);
    stati.add(
      const StatoSincronizzazione(
        fase: FaseSincronizzazione.offline,
        replicaScaricata: false,
      ),
    );
    await tester.pump();

    expect(find.text('Serve una connessione'), findsOneWidget);
    await tester.tap(find.text('Riprova'));
    expect(motore.chiamate, 1);
  });

  testWidgets('un errore lo dice e offre Riprova', (tester) async {
    await mostra(tester);
    stati.add(
      StatoSincronizzazione(
        fase: FaseSincronizzazione.errore,
        replicaScaricata: false,
        prossimoTentativo: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Il download non è riuscito: riprovo a breve.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Riprova'));
    expect(motore.chiamate, 1);
  });
}

class _Motore implements MotoreSincronizzazione {
  int chiamate = 0;

  @override
  Future<EsitoSincronizzazione> sincronizzaOra() async {
    chiamate++;
    return const SincronizzazioneRiuscita(
      EsitoCiclo(inviate: 0, ricevute: 0, scartate: []),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
