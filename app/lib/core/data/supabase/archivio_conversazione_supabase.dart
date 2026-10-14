import 'dart:async';

import 'package:mycomicbrain/core/data/archivio_conversazione.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// La Conversazione di un Profilo autenticato, nelle tabelle Supabase
/// `conversazione`/`messaggio` (ADR-0004): resta online-only e fuori dalla
/// Replica locale (ADR-0008). Le RLS la limitano a chi l'ha creata;
/// `user_id` lo mette il default `auth.uid()`.
///
/// Un solo scrittore (l'Assistente su questo device), quindi
/// [watchMessaggi] rilegge dopo le scritture di questa istanza, senza
/// Realtime.
class ArchivioConversazioneSupabase implements ArchivioConversazione {
  ArchivioConversazioneSupabase(this._client);

  final SupabaseClient _client;
  final _scritture = StreamController<void>.broadcast();

  /// Il tetto `max_rows` di PostgREST: oltre, si legge a pagine.
  static const _pagina = 1000;

  @override
  Future<int> getOrCrea() async {
    final esistenti = await _client
        .from('conversazione')
        .select('id')
        .order('id', ascending: true)
        .limit(1);
    if (esistenti.isNotEmpty) return esistenti.first['id'] as int;
    final creata = await _client
        .from('conversazione')
        .insert({})
        .select('id')
        .single();
    return creata['id'] as int;
  }

  @override
  Future<int> aggiungiMessaggio({
    required int conversazioneId,
    required RuoloMessaggio ruolo,
    required String testo,
    SottotipoSistema? sottotipoSistema,
    List<String> edizioneIds = const [],
    DateTime? createdAt,
  }) async {
    final riga = await _client
        .from('messaggio')
        .insert({
          'conversazione_id': conversazioneId,
          'ruolo': ruolo.name,
          'sottotipo_sistema': sottotipoSistema?.name,
          'testo': testo,
          'edizione_ids': edizioneIds.isEmpty ? null : edizioneIds,
          'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    _scritture.add(null);
    return riga['id'] as int;
  }

  @override
  Stream<List<RigaMessaggio>> watchMessaggi(int conversazioneId) {
    late final StreamController<List<RigaMessaggio>> controller;
    StreamSubscription<void>? sottoscrizione;
    // Le letture in fila: una lettura lenta non sovrascrive una più recente.
    var coda = Future<void>.value();
    void rileggi() {
      coda = coda.then((_) async {
        try {
          final righe = await _leggi(conversazioneId);
          if (!controller.isClosed) controller.add(righe);
        } on Object catch (errore, stack) {
          if (!controller.isClosed) controller.addError(errore, stack);
        }
      });
    }

    controller = StreamController<List<RigaMessaggio>>(
      onListen: () {
        sottoscrizione = _scritture.stream.listen((_) => rileggi());
        rileggi();
      },
      onCancel: () => sottoscrizione?.cancel(),
    );
    return controller.stream;
  }

  Future<List<RigaMessaggio>> _leggi(int conversazioneId) async {
    final righe = <RigaMessaggio>[];
    while (true) {
      final pagina = await _client
          .from('messaggio')
          .select()
          .eq('conversazione_id', conversazioneId)
          .order('created_at', ascending: true)
          .order('id', ascending: true)
          .range(righe.length, righe.length + _pagina - 1);
      righe.addAll(pagina.map(_riga));
      if (pagina.length < _pagina) return righe;
    }
  }

  static RigaMessaggio _riga(Map<String, dynamic> riga) {
    final sottotipo = riga['sottotipo_sistema'] as String?;
    return RigaMessaggio(
      id: riga['id'] as int,
      ruolo: RuoloMessaggio.values.byName(riga['ruolo'] as String),
      sottotipoSistema: sottotipo == null
          ? null
          : SottotipoSistema.values.byName(sottotipo),
      testo: riga['testo'] as String,
      createdAt: DateTime.parse(riga['created_at'] as String).toLocal(),
      edizioneIds: [
        for (final id in riga['edizione_ids'] as List? ?? const [])
          id as String,
      ],
    );
  }

  /// I Messaggi se ne vanno con la cascata della chiave esterna.
  @override
  Future<void> elimina(int conversazioneId) async {
    await _client.from('conversazione').delete().eq('id', conversazioneId);
    _scritture.add(null);
  }

  Future<void> chiudi() => _scritture.close();
}
