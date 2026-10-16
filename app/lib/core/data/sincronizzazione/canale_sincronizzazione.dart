import 'dart:io';
import 'dart:typed_data';

import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/conversione_righe.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Una riga che la Replica deve togliere: eliminata altrove, o scartata dal
/// server perché figlia di una riga eliminata o duplicata.
typedef RigaReplicata = ({String tabella, String id});

/// Un cambiamento di `cambiamenti_da`: `riga` è la riga intera, con
/// `hlc_campi`, oppure null per un'eliminazione.
typedef Cambiamento = ({
  String tabella,
  String id,
  Map<String, Object?>? riga,
});

/// Un'operazione che `applica_modifiche` ha rifiutato per un errore nei dati
/// (classi SQLSTATE `22`/`23`/`42`, #225): `id` è quello dell'operazione.
typedef OperazioneRifiutata = ({String id, String codice, String messaggio});

/// La risposta di `applica_modifiche`: le righe da togliere dalla Replica e
/// le operazioni rifiutate. Le altre operazioni del lotto sono accolte.
typedef EsitoApplicaModifiche = ({
  List<RigaReplicata> eliminate,
  List<OperazioneRifiutata> rifiutate,
});

/// Storage ha rifiutato un file per sempre (troppo grande, tipo non
/// ammesso): riprovare non serve (#225).
class FileRifiutato implements Exception {
  const FileRifiutato(this.codice, this.messaggio);

  final String codice;
  final String messaggio;

  @override
  String toString() => 'FileRifiutato($codice: $messaggio)';
}

typedef PaginaCambiamenti = ({
  List<Cambiamento> cambiamenti,
  String cursore,
  bool altre,
});

/// Le due RPC della Sincronizzazione (ADR-0008, contratto nella sezione
/// "Implementazione"), i file su Storage e la Collezione dell'utente per le
/// chiavi delle cover. Un seam per provare il motore senza Supabase.
abstract interface class CanaleSincronizzazione {
  /// La Collezione di cui l'utente è `owner`.
  Future<String> collectionId();

  /// Applica [ops] in una transazione. Un'operazione con un errore nei dati
  /// è rifiutata da sola; ogni altro errore annulla il lotto e arriva come
  /// eccezione, transitoria. [versioneApp] finisce nel registro dei rifiuti.
  Future<EsitoApplicaModifiche> applicaModifiche(
    List<Map<String, Object?>> ops, {
    required String versioneApp,
  });

  /// La riga [id] di [tabella] com'è su Supabase, come la porta
  /// `cambiamenti_da`; null se il server non ce l'ha.
  Future<Map<String, Object?>?> riga(String tabella, String id);

  /// Annota in `rifiuti_sincronizzazione` un file che Storage ha rifiutato.
  Future<void> registraRifiutoFile({
    required String file,
    required FileRifiutato rifiuto,
    required String versioneApp,
  });

  Future<PaginaCambiamenti> cambiamentiDa(String? cursore, {int limite});

  /// Carica [file] in [bucket] con [chiave], sovrascrivendo: la chiave
  /// dipende solo dal nome del file, quindi ripetere l'upload non cambia
  /// nulla. Lancia [FileRifiutato] se Storage non accetterà mai il file.
  Future<void> caricaFile(BucketImmagine bucket, String chiave, File file);

  /// I byte dell'oggetto [chiave] di [bucket]; null se non esiste (o non è
  /// visibile all'utente).
  Future<Uint8List?> scaricaFile(BucketImmagine bucket, String chiave);
}

class CanaleSupabase implements CanaleSincronizzazione {
  CanaleSupabase(this._client, {required this.userId});

  final SupabaseClient _client;
  final String userId;

  /// Quanto è grande la collezione sul server: le righe delle tabelle
  /// replicate, cioè quelle che il primo download porterà, e i fumetti (le
  /// Copie). Serve all'avanzamento del primo download (#217).
  Future<({int righe, int fumetti})> dimensioni() async {
    final tabelle = RegistroModifiche.tabelleReplicate.toList();
    final conteggi = await Future.wait([
      for (final t in tabelle) _client.from(t).count(),
    ]);
    return (
      righe: conteggi.fold<int>(0, (a, b) => a + b),
      fumetti: conteggi[tabelle.indexOf('copie')],
    );
  }

  @override
  Future<String> collectionId() async {
    final riga = await _client
        .from('collection_members')
        .select('collection_id')
        .eq('user_id', userId)
        .eq('role', 'owner')
        .single();
    return riga['collection_id'] as String;
  }

  @override
  Future<EsitoApplicaModifiche> applicaModifiche(
    List<Map<String, Object?>> ops, {
    required String versioneApp,
  }) async {
    final esito = await _client.rpc<Map<String, dynamic>>(
      'applica_modifiche',
      params: {'ops': ops, 'versione_app': versioneApp},
    );
    return (
      eliminate: [
        for (final e
            in (esito['eliminate'] as List).cast<Map<String, dynamic>>())
          (tabella: e['tabella'] as String, id: e['id'] as String),
      ],
      rifiutate: [
        for (final r
            in ((esito['rifiutate'] as List?) ?? const [])
                .cast<Map<String, dynamic>>())
          (
            id: r['id'] as String,
            codice: r['codice'] as String,
            messaggio: r['messaggio'] as String,
          ),
      ],
    );
  }

  @override
  Future<Map<String, Object?>?> riga(String tabella, String id) =>
      _client.from(tabella).select().eq('id', id).maybeSingle();

  @override
  Future<void> registraRifiutoFile({
    required String file,
    required FileRifiutato rifiuto,
    required String versioneApp,
  }) => _client.from('rifiuti_sincronizzazione').insert({
    'file': file,
    'codice': rifiuto.codice,
    'messaggio': rifiuto.messaggio,
    'versione_app': versioneApp,
  });

  @override
  Future<PaginaCambiamenti> cambiamentiDa(
    String? cursore, {
    int limite = 1000,
  }) async {
    final pagina = await _client.rpc<Map<String, dynamic>>(
      'cambiamenti_da',
      params: {'cursore': cursore, 'limite': limite},
    );
    return (
      cambiamenti: [
        for (final c
            in (pagina['cambiamenti'] as List).cast<Map<String, dynamic>>())
          (
            tabella: c['tabella'] as String,
            id: c['id'] as String,
            riga: (c['riga'] as Map?)?.cast<String, Object?>(),
          ),
      ],
      cursore: pagina['cursore'] as String,
      altre: pagina['altre'] as bool,
    );
  }

  @override
  Future<void> caricaFile(
    BucketImmagine bucket,
    String chiave,
    File file,
  ) async {
    try {
      await _client.storage
          .from(bucket.name)
          .upload(
            chiave,
            file,
            fileOptions: FileOptions(
              contentType: switch (p.extension(chiave).toLowerCase()) {
                '.png' => 'image/png',
                '.webp' => 'image/webp',
                _ => 'image/jpeg',
              },
              upsert: true,
            ),
          );
    } on StorageException catch (e) {
      if (_rifiutoDefinitivo(e)) {
        throw FileRifiutato(e.statusCode ?? '4xx', e.message);
      }
      rethrow;
    }
  }

  /// Un 4xx che riprovare non cambierà: non la sessione scaduta (Storage la
  /// riporta anche come 400 con "jwt"), né un timeout o un limite di
  /// richieste.
  static bool _rifiutoDefinitivo(StorageException e) {
    final codice = int.tryParse(e.statusCode ?? '');
    if (codice == null || codice < 400 || codice >= 500) return false;
    if (const {401, 408, 429}.contains(codice)) return false;
    return !RegExp('jwt|token', caseSensitive: false).hasMatch(e.message);
  }

  @override
  Future<Uint8List?> scaricaFile(BucketImmagine bucket, String chiave) async {
    try {
      return await _client.storage.from(bucket.name).download(chiave);
    } on StorageException catch (e) {
      // Storage risponde 400 "Object not found" oltre a 404.
      if (e.statusCode == '400' || e.statusCode == '404') return null;
      rethrow;
    }
  }
}
