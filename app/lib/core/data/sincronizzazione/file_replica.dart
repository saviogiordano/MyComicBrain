import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/percorso_locale.dart' as percorso_locale;
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/conversione_righe.dart';
import 'package:mycomicbrain/core/data/uuid_v7.dart';

/// I file della Replica locale su Storage (ADR-0008): la coda degli upload,
/// che la Sincronizzazione svuota prima del push, e il download delle cover
/// arrivate col pull.
///
/// I percorsi nella Replica sono relativi alla cartella del Profilo
/// (`cartella`), come li risolve `DriftComicsRepository`.
class FileReplica {
  FileReplica({
    required AppDatabase db,
    required CanaleSincronizzazione canale,
    required Future<Directory> Function() cartella,
    this.paralleli = 4,
  }) : _db = db,
       _canale = canale,
       _cartella = cartella;

  final AppDatabase _db;
  final CanaleSincronizzazione _canale;
  final Future<Directory> Function() _cartella;

  /// Quanti download alla volta.
  final int paralleli;

  /// Le cover che Storage non ha (il device che le ha create non le ha
  /// ancora caricate, o le ha perse): non si richiedono di nuovo finché il
  /// motore resta in vita.
  final _assenti = <String>{};

  /// Carica su Storage i file in coda, ciascuno con la chiave che il push
  /// manda al server, e li toglie dalla coda. Un file che non c'è più sul
  /// device esce dalla coda senza upload: sugli altri device resterà il
  /// segnaposto. Così anche un file che Storage rifiuta per sempre (troppo
  /// grande, tipo non ammesso): il rifiuto si annota sul server con
  /// [versioneApp] (#225). Un altro errore (rete) lascia in coda i file non
  /// ancora caricati.
  Future<void> caricaInCoda(
    ConversioneRighe conversione, {
    required String versioneApp,
  }) async {
    for (final inCoda in await _db.select(_db.codaFileTable).get()) {
      final bucket = BucketImmagine.values.byName(inCoda.bucket);
      final file = File(
        await percorso_locale.risolvi(inCoda.percorso, _cartella),
      );
      if (file.existsSync()) {
        final chiave = conversione.chiaveStorage(bucket, inCoda.percorso);
        try {
          await _canale.caricaFile(bucket, chiave, file);
        } on FileRifiutato catch (rifiuto) {
          await _canale.registraRifiutoFile(
            file: '${bucket.name}/$chiave',
            rifiuto: rifiuto,
            versioneApp: versioneApp,
          );
        }
      }
      await (_db.delete(_db.codaFileTable)..where(
            (f) =>
                f.bucket.equals(inCoda.bucket) &
                f.percorso.equals(inCoda.percorso),
          ))
          .go();
    }
  }

  /// Scarica da Storage le cover della Replica che mancano sul device e le
  /// salva al loro percorso, [paralleli] alla volta. [avanzamento] riceve
  /// quante ne sono arrivate su quante ne mancavano. Le immagini delle
  /// Scansioni restano sul device che le ha scattate (ADR-0008).
  ///
  /// Man mano che arrivano, le query su Edizioni e Serie si rileggono, così
  /// la UI sostituisce il segnaposto. Un errore (rete) interrompe il
  /// download: le cover arrivate restano, le altre al prossimo giro. Si
  /// ferma anche quando [interrompi] risponde true (il logout).
  Future<void> scaricaCover(
    ConversioneRighe conversione, {
    void Function(int scaricate, int totale)? avanzamento,
    bool Function()? interrompi,
  }) async {
    final mancanti = await _coverMancanti();
    if (mancanti.isEmpty) return;
    var scaricate = 0;
    avanzamento?.call(scaricate, mancanti.length);
    final daNotificare = Stopwatch()..start();
    try {
      for (var i = 0; i < mancanti.length; i += paralleli) {
        if (interrompi?.call() ?? false) return;
        await Future.wait([
          for (final (percorso, destinazione)
              in mancanti.skip(i).take(paralleli))
            _scarica(conversione, percorso, destinazione).then((_) {
              avanzamento?.call(++scaricate, mancanti.length);
            }),
        ]);
        if (daNotificare.elapsed >= const Duration(seconds: 1)) {
          _notifica();
          daNotificare.reset();
        }
      }
    } finally {
      _notifica();
    }
  }

  Future<void> _scarica(
    ConversioneRighe conversione,
    String percorso,
    File destinazione,
  ) async {
    final chiave = conversione.chiaveStorage(BucketImmagine.covers, percorso);
    final bytes = await _canale.scaricaFile(BucketImmagine.covers, chiave);
    if (bytes == null) {
      _assenti.add(percorso);
      return;
    }
    await destinazione.parent.create(recursive: true);
    // Scrittura atomica: un file a metà sarebbe mostrato per sempre.
    final temporaneo = File('${destinazione.path}.${uuidV7()}.tmp');
    await temporaneo.writeAsBytes(bytes, flush: true);
    await temporaneo.rename(destinazione.path);
  }

  /// Le cover di Edizioni e Serie che non sono sul device, con il file in
  /// cui salvarle.
  Future<List<(String, File)>> _coverMancanti() async {
    final percorsi = await _db
        .customSelect(
          'SELECT cover_image AS p FROM edizioni WHERE cover_image IS NOT NULL '
          'UNION SELECT cover_image FROM serie WHERE cover_image IS NOT NULL',
          readsFrom: {_db.edizioni, _db.serieTable},
        )
        .map((r) => r.read<String>('p'))
        .get();
    return [
      for (final percorso in percorsi)
        if (!percorso.startsWith('http://') &&
            !percorso.startsWith('https://') &&
            !_assenti.contains(percorso))
          if (File(await percorso_locale.risolvi(percorso, _cartella))
              case final file when !file.existsSync())
            (percorso, file),
    ];
  }

  void _notifica() => _db.notifyUpdates({
    TableUpdate.onTable(_db.edizioni),
    TableUpdate.onTable(_db.serieTable),
  });
}
