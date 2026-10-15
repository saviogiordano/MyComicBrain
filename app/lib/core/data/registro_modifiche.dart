import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/uuid_v7.dart';

/// Che cosa ha fatto una voce del registro delle Modifiche in sospeso.
enum TipoVoceRegistro { inserimento, modifica, eliminazione }

/// Il registro delle Modifiche in sospeso della Replica locale (ADR-0008).
///
/// Lo scrivono dei trigger SQLite `TEMP`, installati da [installa] a ogni
/// apertura del database come Replica: vivono solo nella connessione, quindi
/// non finiscono nel file e la Modalità locale non li ha mai. Catturano ogni
/// scrittura sulle [tabelleReplicate], comprese le transazioni multi-tabella
/// come `confermaCandidato`, senza toccare i metodi del repository.
///
/// Ogni voce porta un timestamp HLC nel formato del server
/// (`<ms su 13 cifre>-<contatore su 4 cifre>-<id del device>`), calcolato
/// dal trigger stesso sull'orologio persistito in `orologio_hlc`: avanza col
/// tempo del device, il contatore separa le scritture nello stesso
/// millisecondo, e [ricevi] lo porta oltre i timestamp arrivati da altri
/// device.
class RegistroModifiche {
  RegistroModifiche(this._db);

  final AppDatabase _db;

  /// Le tabelle sincronizzate con Supabase, con gli stessi nomi (ADR-0008):
  /// tutto il dominio tranne Conversazione e Messaggi.
  static const tabelleReplicate = {
    'opere',
    'serie',
    'edizioni',
    'copie',
    'creator',
    'comic_creator',
    'tag',
    'edizione_tag',
    'character',
    'comic_character',
    'edizione_genere',
    'valore_stimato',
    'scansioni',
    'analisi_copertina',
    'identificazione',
    'candidati',
  };

  /// Crea l'orologio alla prima apertura e (ri)crea i trigger, così seguono
  /// sempre le colonne dello schema corrente. La chiama `AppDatabase` prima
  /// di aprirsi come Replica.
  Future<void> installa() async {
    final dispositivo = uuidV7();
    await _db.customStatement(
      'INSERT INTO orologio_hlc (id, dispositivo, ultimo) '
      "SELECT 1, ?1, '0000000000000-0000-' || ?1 "
      'WHERE NOT EXISTS (SELECT 1 FROM orologio_hlc)',
      [dispositivo],
    );
    await _db.customStatement(
      'CREATE TEMP TABLE IF NOT EXISTS registro_sospeso (x INTEGER)',
    );
    for (final tabella in _db.allTables) {
      final nome = tabella.actualTableName;
      if (!tabelleReplicate.contains(nome)) continue;
      final colonne = [
        for (final c in tabella.$columns)
          if (c.$name != 'id') c.$name,
      ];
      for (final sql in _trigger(nome, colonne)) {
        await _db.customStatement(sql);
      }
    }
  }

  /// Le voci in sospeso, nell'ordine in cui vanno caricate.
  Future<List<VoceRegistro>> voci() => (_db.select(
    _db.registroModificheTable,
  )..orderBy([(v) => OrderingTerm.asc(v.sequenza)])).get();

  /// Quante righe hanno Modifiche in sospeso: è il numero che l'avviso al
  /// logout e l'indicatore della Sincronizzazione mostrano. Più scritture
  /// sulla stessa riga contano una volta sola.
  Future<int> conteggio() => _conteggio().getSingle();

  /// Come [conteggio], aggiornato a ogni scrittura sulla Replica.
  Stream<int> watchConteggio() => _conteggio().watchSingle();

  Selectable<int> _conteggio() => _db
      .customSelect(
        'SELECT count(*) AS n FROM '
        '(SELECT DISTINCT tabella, riga FROM registro_modifiche)',
        // I trigger scrivono il registro senza che drift lo sappia: lo
        // stream si rilegge a ogni scrittura sulle tabelle replicate.
        readsFrom: {
          _db.registroModificheTable,
          for (final t in _db.allTables)
            if (tabelleReplicate.contains(t.actualTableName)) t,
        },
      )
      .map((r) => r.read<int>('n'));

  /// Toglie dal registro le voci [ids], accolte da `applica_modifiche`.
  Future<void> rimuovi(Iterable<String> ids) => (_db.delete(
    _db.registroModificheTable,
  )..where((v) => v.id.isIn(ids))).go();

  /// Esegue [azione] in una transazione le cui scritture non finiscono nel
  /// registro: è il modo di applicare alla Replica ciò che arriva da
  /// Supabase senza rigenerarlo come Modifica in sospeso.
  Future<T> senzaRegistro<T>(Future<T> Function() azione) =>
      _db.transaction(() async {
        await _db.customStatement('INSERT INTO registro_sospeso VALUES (1)');
        try {
          return await azione();
        } finally {
          await _db.customStatement('DELETE FROM registro_sospeso');
        }
      });

  /// Porta l'orologio oltre [hlc], un timestamp arrivato da Supabase: la
  /// prossima scrittura locale avrà un timestamp più recente. Un timestamp
  /// più vecchio dell'orologio non cambia nulla.
  Future<void> ricevi(String hlc) {
    if (!_formatoHlc.hasMatch(hlc)) {
      throw ArgumentError.value(hlc, 'hlc', 'non è un timestamp HLC');
    }
    return _db.customStatement(
      'UPDATE orologio_hlc SET ultimo = substr(?1, 1, 18) || dispositivo '
      'WHERE substr(?1, 1, 18) > substr(ultimo, 1, 18)',
      [hlc],
    );
  }

  /// L'id del device nei timestamp HLC di questa Replica.
  Future<String> dispositivo() async =>
      (await _db.select(_db.orologioHlcTable).getSingle()).dispositivo;

  static final _formatoHlc = RegExp(r'^\d{13}-\d{4}-.+$');

  // --- Trigger -------------------------------------------------------------

  /// I tre trigger di [tabella]. Ogni trigger fa avanzare l'orologio e poi
  /// scrive la voce con il nuovo timestamp.
  static List<String> _trigger(String tabella, List<String> colonne) {
    const attivo = 'NOT EXISTS (SELECT 1 FROM registro_sospeso)';
    final cambiate = colonne.map((c) => 'OLD."$c" IS NOT NEW."$c"');
    final tutte = colonne.map((c) => "'$c', NEW.\"$c\"").join(', ');
    final soloCambiate = colonne
        .map(
          (c) =>
              "SELECT '$c' AS k, NEW.\"$c\" AS v "
              'WHERE OLD."$c" IS NOT NEW."$c"',
        )
        .join(' UNION ALL ');

    String crea(String nome, String evento, String when, String voce) =>
        '''
CREATE TEMP TRIGGER registro_${tabella}_$nome AFTER $evento ON "$tabella"
WHEN $when
BEGIN
  $_avanzaOrologio;
  $voce;
END''';

    String voce(String riga, TipoVoceRegistro tipo, String valori) =>
        'INSERT INTO registro_modifiche (id, tabella, riga, tipo, valori, hlc) '
        "SELECT $_idOperazione, '$tabella', $riga, '${tipo.name}', $valori, "
        'ultimo FROM orologio_hlc';

    return [
      for (final nome in ['inserimento', 'modifica', 'eliminazione'])
        'DROP TRIGGER IF EXISTS temp.registro_${tabella}_$nome',
      crea(
        'inserimento',
        'INSERT',
        attivo,
        voce('NEW.id', TipoVoceRegistro.inserimento, 'json_object($tutte)'),
      ),
      crea(
        'modifica',
        'UPDATE',
        '$attivo AND (${cambiate.join(' OR ')})',
        voce(
          'NEW.id',
          TipoVoceRegistro.modifica,
          '(SELECT json_group_object(k, v) FROM ($soloCambiate))',
        ),
      ),
      crea(
        'eliminazione',
        'DELETE',
        attivo,
        voce('OLD.id', TipoVoceRegistro.eliminazione, 'NULL'),
      ),
    ];
  }

  /// Il prossimo timestamp HLC: il tempo del device se è avanti
  /// sull'orologio, altrimenti lo stesso millisecondo con il contatore +1
  /// (e il millisecondo dopo se il contatore è pieno). `'now'` resta fermo
  /// per tutta un'istruzione, quindi una UPDATE su più righe fa avanzare il
  /// contatore.
  static const _avanzaOrologio =
      '''
UPDATE orologio_hlc SET ultimo = printf('%013d-%04d-',
    CASE WHEN $_ora > $_ms THEN $_ora WHEN $_contatore < 9999 THEN $_ms ELSE $_ms + 1 END,
    CASE WHEN $_ora > $_ms THEN 0 WHEN $_contatore < 9999 THEN $_contatore + 1 ELSE 0 END
  ) || dispositivo''';

  static const _ora =
      "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";
  static const _ms = 'CAST(substr(ultimo, 1, 13) AS INTEGER)';
  static const _contatore = 'CAST(substr(ultimo, 15, 4) AS INTEGER)';

  /// Un uuid v7 con il millisecondo dell'orologio, per l'id dell'operazione
  /// (`operazioni_sincronizzate` sul server è per uuid).
  static const _idOperazione =
      "printf('%08x-%04x-7%03x-%04x-%012x', "
      'CAST(substr(ultimo, 1, 13) AS INTEGER) >> 16, '
      'CAST(substr(ultimo, 1, 13) AS INTEGER) & 65535, '
      'random() & 4095, 32768 | (random() & 16383), '
      'random() & 281474976710655)';
}
