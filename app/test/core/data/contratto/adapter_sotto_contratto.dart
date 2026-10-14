import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/exchange_rate_client.dart';
import 'package:path/path.dart' as p;

/// Un adapter di [ComicsRepository] su cui gira la suite di contratto
/// (ADR-0007). Ogni area della suite è un `*_repository_test.dart` che
/// espone `contratto<Area>(CreaAdapter)`: il suo `main` la esegue su
/// [creaAdapterDriftInMemoria]; le aree che cambiano per un Profilo
/// autenticato girano anche su `creaAdapterProfiloLocale`. Ogni test parte
/// da dati vuoti.
abstract interface class AdapterSottoContratto {
  ComicsRepository get repo;

  /// Un altro repository sugli stessi dati, con dipendenze sostituite (cover
  /// da una cartella temporanea, tasso di cambio fisso, ...).
  ComicsRepository repoCon({
    CopertinaDownloader? copertinaDownloader,
    ExchangeRateClient? exchangeRateClient,
  });

  /// Il database drift dietro l'adapter, per i test che preparano o
  /// verificano righe senza passare dall'interfaccia.
  AppDatabase get drift;

  /// Il percorso di un file immagine nuovo di nome [nome], come quello che
  /// `ScansioneStorage` passa ad `aggiungiScansione`.
  Future<String> immagineScansione(String nome);

  Future<void> chiudi();
}

/// Un JPEG minimo, sufficiente per Storage (che controlla solo il tipo).
const bytesImmagineScansione = [0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xD9];

/// Scrive [nome] in [cartella] con [bytesImmagineScansione].
Future<String> scriviImmagineScansione(Directory cartella, String nome) async {
  final file = File(p.join(cartella.path, nome));
  await file.writeAsBytes(bytesImmagineScansione);
  return file.path;
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

  Directory? _scansioni;

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
  Future<String> immagineScansione(String nome) async =>
      scriviImmagineScansione(
        _scansioni ??= await Directory.systemTemp.createTemp(
          'contratto_scansioni_',
        ),
        nome,
      );

  @override
  Future<void> chiudi() async {
    await drift.close();
    await _scansioni?.delete(recursive: true);
  }
}
