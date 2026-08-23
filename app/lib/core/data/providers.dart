import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/analisi_copertina_pipeline.dart';
import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_provider_config.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/image_crop_service.dart';
import 'package:mycomicbrain/core/data/openai_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/scansione_storage.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final comicsRepositoryProvider = Provider<ComicsRepository>((ref) {
  return ComicsRepository(ref.watch(appDatabaseProvider));
});

final imageCropServiceProvider = Provider<ImageCropService>((ref) => ImageCropService());

final scansioneStorageProvider = Provider<ScansioneStorage>((ref) => ScansioneStorage());

final claudeCoverAnalysisClientProvider = Provider<ClaudeCoverAnalysisClient>(
  (ref) => ClaudeCoverAnalysisClient(),
);

final openAiCoverAnalysisClientProvider = Provider<OpenAiCoverAnalysisClient>(
  (ref) => OpenAiCoverAnalysisClient(),
);

/// Il client del provider AI configurato per l'Analisi Copertina — Claude di
/// default, OpenAI se `--dart-define=COVER_ANALYSIS_PROVIDER=openai` (vedi
/// `CoverAnalysisProviderConfig`). Nessuna UI per la scelta.
final coverAnalysisClientProvider = Provider<CoverAnalysisClient>((ref) {
  return switch (CoverAnalysisProviderConfig.kind) {
    CoverAnalysisProviderKind.openai => ref.watch(openAiCoverAnalysisClientProvider),
    CoverAnalysisProviderKind.claude => ref.watch(claudeCoverAnalysisClientProvider),
  };
});

/// Pipeline di analisi copertina di fine batch (§6.1, §6.2, #32, #49),
/// triggerata da "Fine" nel riepilogo.
final analisiCopertinaPipelineProvider = Provider<AnalisiCopertinaPipeline>((ref) {
  return AnalisiCopertinaPipeline(
    repository: ref.watch(comicsRepositoryProvider),
    client: ref.watch(coverAnalysisClientProvider),
  );
});

/// Lo stato reale dell'Analisi Copertina di una Scansione, per percorso
/// immagine — usato dal riepilogo per riflettere `In sospeso`/`In corso`/
/// `Completata`/`Fallita` invece di un placeholder statico.
final StreamProviderFamily<StatoAnalisiScansione, String> statoAnalisiCopertinaProvider =
    StreamProvider.family<StatoAnalisiScansione, String>((ref, image) {
      return ref.watch(comicsRepositoryProvider).watchStatoAnalisiCopertina(image);
    });
