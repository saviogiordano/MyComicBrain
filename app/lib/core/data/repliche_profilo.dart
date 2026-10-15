import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Le Replica locali dei Profili autenticati su questo device (ADR-0008):
/// per ogni Profilo una cartella `profili/<user_id>/` nei dati
/// dell'applicazione, con la Replica (`replica.sqlite`) e le cover salvate
/// sul device, e una con lo stesso nome nella cache, per i file scaricati da
/// Storage. Cancellare un Profilo dal device vuol dire cancellare le due
/// cartelle.
///
/// Apre ogni Replica una sola volta e la tiene aperta finché non viene
/// cancellata o chiusa con [chiudi].
class ReplicheProfilo {
  ReplicheProfilo({
    Future<Directory> Function()? cartellaDati,
    Future<Directory> Function()? cartellaCache,
    QueryExecutor Function(Future<Directory> Function() cartella)? apri,
  }) : _cartellaDati = cartellaDati ?? getApplicationSupportDirectory,
       _cartellaCache = cartellaCache ?? getApplicationCacheDirectory,
       _apri = apri ?? _apriConDriftFlutter;

  final Future<Directory> Function() _cartellaDati;
  final Future<Directory> Function() _cartellaCache;

  /// Apre `replica.sqlite` nella cartella data; sostituibile nei test, dove
  /// `drift_flutter` non ha i suoi plugin.
  final QueryExecutor Function(Future<Directory> Function() cartella) _apri;
  final _aperte = <String, AppDatabase>{};

  /// La Replica del Profilo [idUtente], creata vuota se non esiste ancora.
  AppDatabase database(String idUtente) => _aperte.putIfAbsent(
    idUtente,
    () => AppDatabase.replica(_apri(() => cartellaDati(idUtente))),
  );

  static QueryExecutor _apriConDriftFlutter(
    Future<Directory> Function() cartella,
  ) => driftDatabase(
    name: nomeReplica,
    native: DriftNativeOptions(databaseDirectory: cartella),
  );

  /// Il nome del file della Replica, senza `.sqlite`.
  static const nomeReplica = 'replica';

  /// La cartella dei dati del Profilo: la base dei percorsi relativi delle
  /// cover salvate nella sua Replica.
  Future<Directory> cartellaDati(String idUtente) =>
      _sottocartella(_cartellaDati, idUtente);

  /// La cartella della cache del Profilo, per i file scaricati da Storage.
  Future<Directory> cartellaCache(String idUtente) =>
      _sottocartella(_cartellaCache, idUtente);

  Future<Directory> _sottocartella(
    Future<Directory> Function() base,
    String idUtente,
  ) async {
    final cartella = Directory(
      p.join((await base()).path, 'profili', idUtente),
    );
    await cartella.create(recursive: true);
    return cartella;
  }

  /// Chiude la Replica di [idUtente] e ne cancella le cartelle: logout ed
  /// eliminazione dell'account (ADR-0008).
  Future<void> cancella(String idUtente) async {
    await _aperte.remove(idUtente)?.close();
    for (final base in [_cartellaDati, _cartellaCache]) {
      final cartella = Directory(
        p.join((await base()).path, 'profili', idUtente),
      );
      if (cartella.existsSync()) await cartella.delete(recursive: true);
    }
  }

  Future<void> chiudi() async {
    final aperte = [..._aperte.values];
    _aperte.clear();
    for (final db in aperte) {
      await db.close();
    }
  }
}
