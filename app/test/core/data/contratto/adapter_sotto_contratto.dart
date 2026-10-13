import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/exchange_rate_client.dart';

/// Un adapter di [ComicsRepository] su cui gira la suite di contratto
/// (ADR-0007). Ogni area della suite è un `*_repository_test.dart` che
/// espone `contratto<Area>(CreaAdapter)`: il suo `main` la esegue su
/// [creaAdapterDriftInMemoria], l'adapter Supabase la esegue con la propria
/// factory. Ogni test parte da dati vuoti.
abstract interface class AdapterSottoContratto {
  ComicsRepository get repo;

  /// Un altro repository sugli stessi dati, con dipendenze sostituite (cover
  /// da una cartella temporanea, tasso di cambio fisso, ...).
  ComicsRepository repoCon({
    CopertinaDownloader? copertinaDownloader,
    ExchangeRateClient? exchangeRateClient,
  });

  /// Il database drift dietro l'adapter, per i test che preparano o
  /// verificano righe senza passare dall'interfaccia. Solo l'adapter drift
  /// lo espone: su un altro adapter quei test falliscono finché non vengono
  /// riscritti sull'interfaccia, come richiede la parità di ADR-0007.
  AppDatabase get drift;

  Future<void> chiudi();
}

typedef CreaAdapter = Future<AdapterSottoContratto> Function();

/// [DriftComicsRepository] su un database SQLite in memoria.
Future<AdapterSottoContratto> creaAdapterDriftInMemoria() async =>
    _AdapterDriftInMemoria(
      AppDatabase(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      ),
    );

class _AdapterDriftInMemoria implements AdapterSottoContratto {
  _AdapterDriftInMemoria(this.drift) : repo = DriftComicsRepository(drift);

  @override
  final AppDatabase drift;

  @override
  final ComicsRepository repo;

  @override
  ComicsRepository repoCon({
    CopertinaDownloader? copertinaDownloader,
    ExchangeRateClient? exchangeRateClient,
  }) => DriftComicsRepository(
    drift,
    copertinaDownloader: copertinaDownloader,
    exchangeRateClient: exchangeRateClient,
  );

  @override
  Future<void> chiudi() => drift.close();
}
