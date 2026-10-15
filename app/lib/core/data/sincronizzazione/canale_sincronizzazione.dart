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
/// "Implementazione"), più la Collezione dell'utente per le chiavi delle
/// cover. Un seam per provare il motore senza Supabase.
abstract interface class CanaleSincronizzazione {
  /// La Collezione di cui l'utente è `owner`.
  Future<String> collectionId();

  /// Applica [ops] in una transazione e restituisce le righe da togliere.
  Future<List<RigaReplicata>> applicaModifiche(List<Map<String, Object?>> ops);

  Future<PaginaCambiamenti> cambiamentiDa(String? cursore, {int limite});
}

class CanaleSupabase implements CanaleSincronizzazione {
  CanaleSupabase(this._client, {required this.userId});

  final SupabaseClient _client;
  final String userId;

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
}
