import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/analisi_copertina_pipeline.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';

class _PipelineFinta implements AnalisiCopertinaPipeline {
  var avvii = 0;

  @override
  Future<void> avviaInAttesa() async => avvii++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SettingsRepository settings;
  late _PipelineFinta pipeline;

  ProviderContainer contenitore({bool senzaRete = false}) {
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        analisiCopertinaPipelineProvider.overrideWithValue(pipeline),
        senzaReteProvider.overrideWithValue(senzaRete),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    settings = SettingsRepository.inMemoria();
    pipeline = _PipelineFinta();
  });

  test('parte spenta', () {
    expect(contenitore().read(aiAbilitataProvider), isFalse);
  });

  test('riaccesa salva la scelta e riprende le Scansioni in attesa', () async {
    final container = contenitore();

    await container.read(aiAbilitataProvider.notifier).imposta(abilitata: true);

    expect(container.read(aiAbilitataProvider), isTrue);
    expect(settings.aiAbilitata, isTrue);
    expect(pipeline.avvii, 1);
  });

  test('riaccesa senza rete aspetta la Sincronizzazione', () async {
    await contenitore(
      senzaRete: true,
    ).read(aiAbilitataProvider.notifier).imposta(abilitata: true);

    expect(pipeline.avvii, 0);
  });

  test('spegnendola non parte nulla', () async {
    await settings.impostaAiAbilitata(abilitata: true);

    await contenitore()
        .read(aiAbilitataProvider.notifier)
        .imposta(abilitata: false);

    expect(settings.aiAbilitata, isFalse);
    expect(pipeline.avvii, 0);
  });

  test("l'Assistente non risulta configurato con l'AI spenta", () async {
    final container = contenitore();

    expect(await container.read(assistenteConfiguratoProvider.future), isFalse);
  });
}
