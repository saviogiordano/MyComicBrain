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

  /// Applica [ops] in una transazione e restituisce le righe da togliere.
  Future<List<RigaReplicata>> applicaModifiche(List<Map<String, Object?>> ops);

  Future<PaginaCambiamenti> cambiamentiDa(String? cursore, {int limite});

  /// Carica [file] in [bucket] con [chiave], sovrascrivendo: la chiave
  /// dipende solo dal nome del file, quindi ripetere l'upload non cambia
  /// nulla.
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
  Future<List<RigaReplicata>> applicaModifiche(
    List<Map<String, Object?>> ops,
  ) async {
    final esito = await _client.rpc<Map<String, dynamic>>(
      'applica_modifiche',
      params: {'ops': ops},
    );
    return [
      for (final e in (esito['eliminate'] as List).cast<Map<String, dynamic>>())
        (tabella: e['tabella'] as String, id: e['id'] as String),
    ];
  }

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
