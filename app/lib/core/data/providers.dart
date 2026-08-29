import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/analisi_copertina_pipeline.dart';
import 'package:mycomicbrain/core/data/assistente_client.dart';
import 'package:mycomicbrain/core/data/assistente_orchestrator.dart';
import 'package:mycomicbrain/core/data/claude_assistente_client.dart';
import 'package:mycomicbrain/core/data/claude_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/comic_vine_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/identificazione_pipeline.dart';
import 'package:mycomicbrain/core/data/image_crop_service.dart';
import 'package:mycomicbrain/core/data/locale_assistente_client.dart';
import 'package:mycomicbrain/core/data/locale_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/openai_assistente_client.dart';
import 'package:mycomicbrain/core/data/openai_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/openrouter_assistente_client.dart';
import 'package:mycomicbrain/core/data/openrouter_cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/preferences_shared_preferences_adapter.dart';
import 'package:mycomicbrain/core/data/scansione_storage.dart';
import 'package:mycomicbrain/core/data/secure_storage_flutter_adapter.dart';
import 'package:mycomicbrain/core/data/settings_repository.dart';
import 'package:mycomicbrain/core/domain/ai_provider.dart';
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

/// Il `SettingsRepository` (§12, schema deciso su #101, implementato su
/// #105): unico punto di accesso alle Impostazioni per lo schermo omonimo
/// (#107) e per i client AI/ComicVine migrati su #106.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final repository = SettingsRepository(
    preferences: SharedPreferencesAdapter(ref.watch(sharedPreferencesProvider)),
    secureStorage: const FlutterSecureStorageAdapter(),
  );
  // Semina i due ruoli Visivo/Testuale dalla configurazione singola
  // preesistente al primo avvio dopo lo split (ADR-0001, #127) — stesso
  // pattern fire-and-forget di `comicsRepositoryProvider` sotto.
  unawaited(repository.migraSeNecessario());
  return repository;
});

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
  (ref) => ClaudeCoverAnalysisClient(
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

final openAiCoverAnalysisClientProvider = Provider<OpenAiCoverAnalysisClient>(
  (ref) => OpenAiCoverAnalysisClient(
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

final openRouterCoverAnalysisClientProvider =
    Provider<OpenRouterCoverAnalysisClient>(
      (ref) => OpenRouterCoverAnalysisClient(
        settingsRepository: ref.watch(settingsRepositoryProvider),
      ),
    );

final localeCoverAnalysisClientProvider = Provider<LocaleCoverAnalysisClient>(
  (ref) => LocaleCoverAnalysisClient(
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

/// Il client AI per uno specifico [AiProvider], indipendentemente da quale
/// sia l'attivo (§12, deciso dopo #111: la schermata Impostazioni mostra
/// tutti i provider insieme e deve poter verificare la connessione di
/// ciascuna card anche quando non è quella attiva). Punto di override unico
/// per i test, dato che le implementazioni concrete
/// (`claudeCoverAnalysisClientProvider` e affini) sono tipizzate sulla
/// classe concreta e non sull'interfaccia [CoverAnalysisClient].
final ProviderFamily<CoverAnalysisClient, AiProvider>
coverAnalysisClientPerProvider =
    Provider.family<CoverAnalysisClient, AiProvider>((
      ref,
      provider,
    ) {
      return switch (provider) {
        AiProvider.openai => ref.watch(openAiCoverAnalysisClientProvider),
        AiProvider.claude => ref.watch(claudeCoverAnalysisClientProvider),
        AiProvider.openRouter => ref.watch(
          openRouterCoverAnalysisClientProvider,
        ),
        AiProvider.locale => ref.watch(localeCoverAnalysisClientProvider),
      };
    });

/// Il client del provider AI configurato per l'Analisi Copertina, letto a
/// runtime dalle Impostazioni (§12, deciso su #101/#102, migrato su #106) —
/// non più a build-time. Default a Claude quando l'utente non ha ancora
/// scelto un provider (nessuno schermo Impostazioni funzionante prima di
/// #107). OpenRouter/Locale hanno un client implementato da #109.
final coverAnalysisClientProvider = Provider<CoverAnalysisClient>((ref) {
  final providerAi =
      ref
          .watch(settingsRepositoryProvider)
          .providerAi(RuoloProviderAi.visivo) ??
      AiProvider.claude;
  return ref.watch(coverAnalysisClientPerProvider(providerAi));
});

final claudeAssistenteClientProvider = Provider<ClaudeAssistenteClient>(
  (ref) => ClaudeAssistenteClient(
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

final openAiAssistenteClientProvider = Provider<OpenAiAssistenteClient>(
  (ref) => OpenAiAssistenteClient(
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

final openRouterAssistenteClientProvider =
    Provider<OpenRouterAssistenteClient>(
      (ref) => OpenRouterAssistenteClient(
        settingsRepository: ref.watch(settingsRepositoryProvider),
      ),
    );

final localeAssistenteClientProvider = Provider<LocaleAssistenteClient>(
  (ref) => LocaleAssistenteClient(
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
);

/// Il client dell'Assistente per uno specifico [AiProvider] (ruolo
/// [RuoloProviderAi.testuale]), indipendentemente da quale sia l'attivo —
/// stesso motivo di [coverAnalysisClientPerProvider] per il ruolo Visivo.
final ProviderFamily<AssistenteClient, AiProvider> assistenteClientPerProvider =
    Provider.family<AssistenteClient, AiProvider>((ref, provider) {
      return switch (provider) {
        AiProvider.openai => ref.watch(openAiAssistenteClientProvider),
        AiProvider.claude => ref.watch(claudeAssistenteClientProvider),
        AiProvider.openRouter => ref.watch(
          openRouterAssistenteClientProvider,
        ),
        AiProvider.locale => ref.watch(localeAssistenteClientProvider),
      };
    });

/// Il client del Provider AI Testuale configurato per l'Assistente (§10),
/// letto a runtime dalle Impostazioni — stesso pattern di
/// [coverAnalysisClientProvider] per il ruolo Visivo. Default a Claude
/// quando l'utente non ha ancora scelto un provider Testuale.
final assistenteClientProvider = Provider<AssistenteClient>((ref) {
  final providerAi =
      ref
          .watch(settingsRepositoryProvider)
          .providerAi(RuoloProviderAi.testuale) ??
      AiProvider.claude;
  return ref.watch(assistenteClientPerProvider(providerAi));
});

/// Orchestratore dell'Assistente (§10, deciso su
/// [Implementare l'orchestratore LLM Testuale con tool-calling](https://github.com/saviogiordano/MyComicBrain/issues/132)):
/// invia i messaggi dell'utente al Provider AI Testuale configurato,
/// esegue le tool call sulle query di `ComicsRepository` e persiste
/// Conversazione/Messaggio.
final assistenteOrchestratorProvider = Provider<AssistenteOrchestrator>((ref) {
  return AssistenteOrchestrator(
    repository: ref.watch(comicsRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    client: ref.watch(assistenteClientProvider),
  );
});

final comicVineClientProvider = Provider<ComicVineClient>(
  (ref) => ComicVineHttpClient(
    settingsRepository: ref.watch(settingsRepositoryProvider),
  ),
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

/// Se una Scansione è già stata confermata (esiste già una `Copia` che la
/// referenzia, deciso in sessione) — usata dal riepilogo per mostrare
/// "Salvata" al posto di "Completata" e impedire una seconda conferma sulla
/// stessa riga. Per percorso immagine, stesso motivo di
/// [statoAnalisiCopertinaProvider].
final StreamProviderFamily<bool, String> scansioneConfermataProvider =
    StreamProvider.family<bool, String>((ref, image) {
      return ref
          .watch(comicsRepositoryProvider)
          .watchScansioneConfermata(image);
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
