import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/analisi_copertina_pipeline.dart';
import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/comic_vine_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/cover_analysis_provider_config.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/identificazione_pipeline.dart';
import 'package:mycomicbrain/core/data/image_crop_service.dart';
import 'package:mycomicbrain/core/data/openai_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/scansione_storage.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
import 'package:mycomicbrain/core/domain/serie_dettaglio.dart';
import 'package:mycomicbrain/core/domain/serie_lista.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// L'istanza di `SharedPreferences` risolta prima di `runApp` (vedi
/// `main.dart`) e passata come override — usata per la persistenza dei
/// filtri della Collezione (§9, deciso su #85). Il valore di default lancia
/// di proposito: un consumatore che la legge senza che `main.dart` l'abbia
/// sostituita è un errore di bootstrap, non un caso da gestire in UI.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider non sostituito prima di runApp',
  ),
);

final copertinaDownloaderProvider = Provider<CopertinaDownloader>(
  (ref) => CopertinaDownloader(),
);

final comicsRepositoryProvider = Provider<ComicsRepository>((ref) {
  final repository = ComicsRepository(
    ref.watch(appDatabaseProvider),
    copertinaDownloader: ref.watch(copertinaDownloaderProvider),
  );
  // Ripara le Serie duplicate create prima della deduplica di
  // `aggiungiSerie` (bug osservato: il contatore "serie" della Dashboard
  // contava una riga per scansione invece che per collana).
  unawaited(repository.unisciSerieDuplicate());
  return repository;
});

final imageCropServiceProvider = Provider<ImageCropService>(
  (ref) => ImageCropService(),
);

final scansioneStorageProvider = Provider<ScansioneStorage>(
  (ref) => ScansioneStorage(),
);

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
    CoverAnalysisProviderKind.openai => ref.watch(
      openAiCoverAnalysisClientProvider,
    ),
    CoverAnalysisProviderKind.claude => ref.watch(
      claudeCoverAnalysisClientProvider,
    ),
  };
});

final comicVineClientProvider = Provider<ComicVineClient>(
  (ref) => ComicVineHttpClient(),
);

/// Orchestratore dell'Identificazione (§6.3, #53/#57): genera e persiste i
/// Candidati di una Scansione a partire dalla sua Analisi Copertina già
/// `completata`. Agganciato in automatico da `analisiCopertinaPipelineProvider`
/// (#58) — nessun trigger manuale.
final identificazionePipelineProvider = Provider<IdentificazionePipeline>((
  ref,
) {
  return IdentificazionePipeline(
    repository: ref.watch(comicsRepositoryProvider),
    comicVineClient: ref.watch(comicVineClientProvider),
  );
});

/// Pipeline di analisi copertina di fine batch (§6.1, §6.2, #32, #49),
/// triggerata da "Fine" nel riepilogo. A completamento di ogni Analisi
/// Copertina, aggancia subito l'Identificazione (#58).
final analisiCopertinaPipelineProvider = Provider<AnalisiCopertinaPipeline>((
  ref,
) {
  return AnalisiCopertinaPipeline(
    repository: ref.watch(comicsRepositoryProvider),
    client: ref.watch(coverAnalysisClientProvider),
    identificazionePipeline: ref.watch(identificazionePipelineProvider),
  );
});

/// Lo stato reale dell'Analisi Copertina di una Scansione, per percorso
/// immagine — usato dal riepilogo per riflettere `In sospeso`/`In corso`/
/// `Completata`/`Fallita` invece di un placeholder statico.
final StreamProviderFamily<StatoAnalisiScansione, String>
statoAnalisiCopertinaProvider =
    StreamProvider.family<StatoAnalisiScansione, String>((ref, image) {
      return ref
          .watch(comicsRepositoryProvider)
          .watchStatoAnalisiCopertina(image);
    });

/// L'esito osservabile dell'Identificazione di una Scansione (§6.3, schermo
/// di conferma #59), per id — a differenza di [statoAnalisiCopertinaProvider]
/// (per percorso immagine) usa `scansioneId` perché è la chiave con cui il
/// resto del repository dell'Identificazione già lavora.
final StreamProviderFamily<EsitoIdentificazione, int> identificazioneProvider =
    StreamProvider.family<EsitoIdentificazione, int>((ref, scansioneId) {
      return ref
          .watch(comicsRepositoryProvider)
          .watchIdentificazione(scansioneId);
    });

/// L'Analisi Copertina completata di una Scansione, per id — usata da
/// `InserisciManualmentePage` (§6.3, deciso su #63) per precompilare il
/// form col risultato AI invece di lasciarlo vuoto quando né il catalogo
/// interno né ComicVine hanno trovato un candidato affidabile.
final FutureProviderFamily<AnalisiCopertinaTableData, int>
analisiCopertinaProvider =
    FutureProvider.family<AnalisiCopertinaTableData, int>((
      ref,
      scansioneId,
    ) {
      return ref
          .watch(comicsRepositoryProvider)
          .analisiCopertinaPerScansione(scansioneId);
    });

/// L'Edizione con le sue Copie e i suoi Autori per la Scheda del fumetto
/// (§8, deciso su #63/#65/#67/#68), per id — `null` se l'Edizione è stata
/// cancellata.
final StreamProviderFamily<EdizioneDettaglio?, int> edizioneDettaglioProvider =
    StreamProvider.family<EdizioneDettaglio?, int>((ref, edizioneId) {
      return ref.watch(comicsRepositoryProvider).watchEdizione(edizioneId);
    });

/// L'elenco `/serie` (§11, deciso su #97/#98), raggruppato in tre sezioni.
final serieListaProvider = StreamProvider<SerieLista>((ref) {
  return ref.watch(comicsRepositoryProvider).watchSerieLista();
});

/// Il dettaglio `/serie/:id` (§11, deciso su #97/#99), per id — `null` se
/// la Serie è stata cancellata.
final StreamProviderFamily<SerieDettaglio?, int> serieDettaglioProvider =
    StreamProvider.family<SerieDettaglio?, int>((ref, serieId) {
      return ref.watch(comicsRepositoryProvider).watchSerieDettaglio(serieId);
    });
