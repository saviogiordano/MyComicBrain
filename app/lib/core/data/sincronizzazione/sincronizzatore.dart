import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/conversione_righe.dart';

/// Com'è andato un ciclo di Sincronizzazione.
class EsitoCiclo {
  const EsitoCiclo({
    required this.inviate,
    required this.ricevute,
    required this.scartate,
  });

  /// Le voci del registro accolte da `applica_modifiche`.
  final int inviate;

  /// I cambiamenti arrivati col pull, eliminazioni comprese.
  final int ricevute;

  /// Le righe con Modifiche in sospeso che sono state tolte dalla Replica
  /// perché eliminate altrove (o scartate dal server): l'avviso "modifica
  /// non salvata" della UI.
  final List<RigaReplicata> scartate;
}

/// Un ciclo di Sincronizzazione della Replica locale (ADR-0008): push del
/// registro delle Modifiche in sospeso con `applica_modifiche`, poi pull con
/// `cambiamenti_da`, applicato senza rigenerare Modifiche in sospeso. Il
/// primo pull (nessun cursore salvato) è il primo download.
///
/// Non sa nulla di inneschi, rete e tentativi: li gestisce
/// `MotoreSincronizzazione`.
class Sincronizzatore {
  Sincronizzatore({
    required AppDatabase db,
    required CanaleSincronizzazione canale,
    required this.userId,
    this.lottoPush = 200,
    this.paginaPull = 1000,
    DateTime Function()? ora,
  }) : _db = db,
       _canale = canale,
       _registro = RegistroModifiche(db),
       _ora = ora ?? DateTime.now;

  final AppDatabase _db;
  final CanaleSincronizzazione _canale;
  final RegistroModifiche _registro;
  final String userId;
  final int lottoPush;
  final int paginaPull;
  final DateTime Function() _ora;

  ConversioneRighe? _conversione;

  /// Dove è arrivata la Replica; null se non è ancora stata scaricata.
  Future<StatoSincronizzazioneReplica?> stato() =>
      _db.select(_db.statoSincronizzazioneTable).getSingleOrNull();

  /// Push e pull. [avanzamento] riceve quante righe sono arrivate finora,
  /// per il primo download. Un errore lascia la Replica e il registro come
  /// prima del lotto o della pagina che è fallita: il ciclo successivo
  /// riprende da lì.
  Future<EsitoCiclo> sincronizza({
    void Function(int ricevute)? avanzamento,
  }) async {
    final conversione = _conversione ??= ConversioneRighe(
      _db,
      collectionId: await _canale.collectionId(),
      userId: userId,
    );
    final scartate = <RigaReplicata>[];
    final inviate = await _push(conversione, scartate);
    final ricevute = await _pull(conversione, scartate, avanzamento);
    return EsitoCiclo(inviate: inviate, ricevute: ricevute, scartate: scartate);
  }

  // --- Push ----------------------------------------------------------------

  Future<int> _push(
    ConversioneRighe conversione,
    List<RigaReplicata> scartate,
  ) async {
    var inviate = 0;
    while (true) {
      final lotto = (await _registro.voci()).take(lottoPush).toList();
      if (lotto.isEmpty) return inviate;
      final ops = [
        for (final voce in lotto) ?_operazione(conversione, voce),
      ];
      final eliminate = ops.isEmpty
          ? const <RigaReplicata>[]
          : await _canale.applicaModifiche(ops);
      await _registro.senzaRegistro(() async {
        await _registro.rimuovi(lotto.map((v) => v.id));
        for (final riga in eliminate) {
          final scrittaQui = lotto.any(
            (v) =>
                v.tabella == riga.tabella &&
                v.riga == riga.id &&
                v.tipo != TipoVoceRegistro.eliminazione,
          );
          if (await _togli(riga) || scrittaQui) scartate.add(riga);
        }
      });
      inviate += lotto.length;
    }
  }

  /// L'operazione di `applica_modifiche` per [voce]; null per una modifica
  /// che tocca solo colonne che non vanno sul server.
  static Map<String, Object?>? _operazione(
    ConversioneRighe conversione,
    VoceRegistro voce,
  ) {
    final base = {'id': voce.id, 'tabella': voce.tabella, 'riga': voce.riga};
    if (voce.tipo == TipoVoceRegistro.eliminazione) {
      return {...base, 'elimina': true};
    }
    final valori = conversione.perIlServer(
      voce.tabella,
      (jsonDecode(voce.valori!) as Map).cast<String, Object?>(),
    );
    if (valori.isEmpty && voce.tipo == TipoVoceRegistro.modifica) return null;
    return {
      ...base,
      'valori': valori,
      'hlc': {for (final campo in valori.keys) campo: voce.hlc},
    };
  }

  // --- Pull ----------------------------------------------------------------

  Future<int> _pull(
    ConversioneRighe conversione,
    List<RigaReplicata> scartate,
    void Function(int ricevute)? avanzamento,
  ) async {
    // Tutte le pagine prima di scrivere: la Replica non resta mai a metà di
    // un pull, e un figlio arrivato prima del padre trova il padre.
    var cursore = (await stato())?.cursore;
    final cambiamenti = <Cambiamento>[];
    while (true) {
      final pagina = await _canale.cambiamentiDa(cursore, limite: paginaPull);
      cambiamenti.addAll(pagina.cambiamenti);
      cursore = pagina.cursore;
      avanzamento?.call(cambiamenti.length);
      if (!pagina.altre) break;
    }

    await _registro.senzaRegistro(() async {
      final inSospeso = _inSospeso(await _registro.voci());
      String? hlcMassimo;
      for (final c in cambiamenti) {
        final riga = (tabella: c.tabella, id: c.id);
        final sospese = inSospeso[riga];
        if (c.riga == null) {
          if (await _togli(riga) && sospese != null && !sospese.eliminata) {
            scartate.add(riga);
          }
          inSospeso.remove(riga);
          continue;
        }
        // L'eliminazione fatta qui prevale: la porterà il prossimo push.
        if (sospese?.eliminata ?? false) continue;
        for (final hlc in (c.riga!['hlc_campi'] as Map?)?.values ?? const []) {
          if (hlcMassimo == null || (hlc as String).compareTo(hlcMassimo) > 0) {
            hlcMassimo = hlc as String;
          }
        }
        await _scrivi(
          conversione,
          c.tabella,
          conversione.perLaReplica(c.tabella, c.riga!),
          sospese?.campi ?? const {},
          inSospeso,
        );
      }
      await _db
          .into(_db.statoSincronizzazioneTable)
          .insertOnConflictUpdate(
            StatoSincronizzazioneTableCompanion.insert(
              id: const Value(1),
              cursore: cursore!,
              ultima: _ora().toUtc(),
            ),
          );
      if (hlcMassimo != null) await _registro.ricevi(hlcMassimo);
    });
    return cambiamenti.length;
  }

  /// Inserisce o aggiorna la riga arrivata dal server, tranne i campi con
  /// Modifiche in sospeso: il push successivo li porterà al server, che
  /// deciderà quale vince.
  Future<void> _scrivi(
    ConversioneRighe conversione,
    String tabella,
    Map<String, Object?> valori,
    Set<String> campiInSospeso,
    Map<RigaReplicata, _InSospeso> inSospeso,
  ) async {
    final id = valori['id']! as String;
    final info = conversione.tabella(tabella);
    final locale = await _db
        .customSelect(
          'SELECT * FROM "$tabella" WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingleOrNull();

    // Una cover della Replica può stare altrove (la cover presa da una
    // Scansione, un percorso assoluto di prima): se il server ha la chiave
    // dello stesso file, resta il percorso locale.
    for (final MapEntry(key: colonna, value: bucket)
        in (colonneImmagine[tabella] ?? const {}).entries) {
      final attuale = locale?.data[colonna] as String?;
      if (attuale != null &&
          valori[colonna] != null &&
          conversione.chiaveStorage(bucket, attuale) ==
              conversione.chiaveStorage(bucket, valori[colonna]! as String)) {
        valori[colonna] = attuale;
      }
    }

    // La stessa chiave naturale con un altro id (lo stesso collegamento o
    // Valore stimato creato anche qui): vince la riga del server, come in
    // `applica_modifiche`.
    for (final chiave in info.uniqueKeys) {
      final colonne = [for (final c in chiave) c.$name];
      if (colonne.any((c) => valori[c] == null)) continue;
      final doppioni = await _db
          .customSelect(
            'SELECT id FROM "$tabella" WHERE id <> ? AND '
            '${colonne.map((c) => '"$c" = ?').join(' AND ')}',
            variables: [
              Variable(id),
              for (final c in colonne) Variable(valori[c]),
            ],
          )
          .get();
      for (final doppione in doppioni) {
        final riga = (tabella: tabella, id: doppione.read<String>('id'));
        await _togli(riga);
        inSospeso.remove(riga);
      }
    }

    if (locale == null) {
      final colonne = valori.keys.toList();
      await _db.customInsert(
        'INSERT INTO "$tabella" (${colonne.map((c) => '"$c"').join(', ')}) '
        'VALUES (${List.filled(colonne.length, '?').join(', ')})',
        variables: [for (final c in colonne) Variable(valori[c])],
        updates: {info},
      );
      return;
    }
    final daScrivere = [
      for (final c in valori.keys)
        if (c != 'id' && !campiInSospeso.contains(c)) c,
    ];
    if (daScrivere.isEmpty) return;
    await _db.customUpdate(
      'UPDATE "$tabella" SET ${daScrivere.map((c) => '"$c" = ?').join(', ')} '
      'WHERE id = ?',
      variables: [
        for (final c in daScrivere) Variable(valori[c]),
        Variable(id),
      ],
      updates: {info},
      updateKind: UpdateKind.update,
    );
  }

  /// Toglie [riga] dalla Replica e dal registro. Dice se la riga c'era.
  Future<bool> _togli(RigaReplicata riga) async {
    final tolte = await _db.customUpdate(
      'DELETE FROM "${riga.tabella}" WHERE id = ?',
      variables: [Variable(riga.id)],
      updates: {
        _db.allTables.firstWhere((t) => t.actualTableName == riga.tabella),
      },
      updateKind: UpdateKind.delete,
    );
    await (_db.delete(_db.registroModificheTable)..where(
          (v) => v.tabella.equals(riga.tabella) & v.riga.equals(riga.id),
        ))
        .go();
    return tolte > 0;
  }

  static Map<RigaReplicata, _InSospeso> _inSospeso(List<VoceRegistro> voci) {
    final perRiga = <RigaReplicata, _InSospeso>{};
    for (final voce in voci) {
      final stato = perRiga.putIfAbsent(
        (tabella: voce.tabella, id: voce.riga),
        _InSospeso.new,
      );
      if (voce.tipo == TipoVoceRegistro.eliminazione) {
        stato.eliminata = true;
      } else {
        stato.campi.addAll((jsonDecode(voce.valori!) as Map).keys.cast());
      }
    }
    return perRiga;
  }
}

class _InSospeso {
  bool eliminata = false;
  final campi = <String>{};
}
