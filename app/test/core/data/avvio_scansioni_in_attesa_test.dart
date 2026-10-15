import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/analisi_copertina_pipeline.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';

class _FakePipeline implements AnalisiCopertinaPipeline {
  int avvii = 0;

  @override
  Future<void> avviaInAttesa() async => avvii++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Le Scansioni accodate senza rete partono dopo ogni ciclo di
/// Sincronizzazione riuscito: c'è la rete e le immagini sono su Storage
/// (ADR-0008, #210).
void main() {
  late StreamController<StatoSincronizzazione?> stati;
  late _FakePipeline pipeline;
  late ProviderContainer container;

  setUp(() {
    stati = StreamController();
    pipeline = _FakePipeline();
    container = ProviderContainer(
      overrides: [
        statoSincronizzazioneProvider.overrideWith((ref) => stati.stream),
        analisiCopertinaPipelineProvider.overrideWithValue(pipeline),
      ],
    )..read(avvioScansioniInAttesaProvider);
  });

  tearDown(() async {
    container.dispose();
    await stati.close();
  });

  Future<void> emetti(StatoSincronizzazione stato) async {
    stati.add(stato);
    await Future<void>.delayed(Duration.zero);
  }

  test("parte a ogni ciclo riuscito, non all'avvio né offline", () async {
    final ieri = DateTime(2026, 10, 14);
    final oggi = DateTime(2026, 10, 15);

    // L'avvio del motore riporta l'ultima sincronizzazione salvata.
    await emetti(
      StatoSincronizzazione(
        fase: FaseSincronizzazione.ferma,
        replicaScaricata: true,
        ultima: ieri,
      ),
    );
    await emetti(
      StatoSincronizzazione(
        fase: FaseSincronizzazione.offline,
        replicaScaricata: true,
        ultima: ieri,
      ),
    );
    expect(pipeline.avvii, 0);

    await emetti(
      StatoSincronizzazione(
        fase: FaseSincronizzazione.sincronizzata,
        replicaScaricata: true,
        ultima: oggi,
      ),
    );
    expect(pipeline.avvii, 1);

    // Le cover in arrivo riemettono lo stesso ciclo.
    await emetti(
      StatoSincronizzazione(
        fase: FaseSincronizzazione.sincronizzata,
        replicaScaricata: true,
        ultima: oggi,
        cover: (scaricate: 1, totale: 2),
      ),
    );
    expect(pipeline.avvii, 1);

    await emetti(
      StatoSincronizzazione(
        fase: FaseSincronizzazione.sincronizzata,
        replicaScaricata: true,
        ultima: oggi.add(const Duration(minutes: 5)),
      ),
    );
    expect(pipeline.avvii, 2);
  });
}
