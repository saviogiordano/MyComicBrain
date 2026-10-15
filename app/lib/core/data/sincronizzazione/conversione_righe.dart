import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:path/path.dart' as p;

/// Le colonne immagine delle tabelle replicate, con il bucket di Storage
/// dove stanno i loro file (ADR-0007).
const Map<String, Map<String, BucketImmagine>> colonneImmagine = {
  'edizioni': {'cover_image': BucketImmagine.covers},
  'serie': {'cover_image': BucketImmagine.covers},
  'scansioni': {'image': BucketImmagine.scansioni},
};

/// Dove sta un file di una colonna immagine: nella Replica una cartella
/// del Profilo, su Storage un bucket con un prefisso.
enum BucketImmagine {
  /// `copertine/<file>` sul device, `covers/<collection_id>/<file>` su
  /// Storage.
  covers('copertine'),

  /// `scansioni/<file>` sul device, `scansioni/<user_id>/<file>` su
  /// Storage.
  scansioni('scansioni');

  const BucketImmagine(this.cartellaLocale);

  final String cartellaLocale;
}

/// Le colonne lista: in drift JSON in un testo, in Postgres `text[]`.
const _colonneLista = {
  'analisi_copertina': {
    'characters',
    'cover_style_tags',
    'visual_element_tags',
  },
};

/// Colonne drift che non vanno su Supabase: `scansioni.user_id` è un intero
/// mai usato, su Supabase è l'uuid dell'utente e lo mette il server;
/// `candidati.description` è una colonna morta (#73) che Supabase non ha, e
/// `applica_modifiche` rifiuterebbe l'intero lotto (#210).
const _soloDrift = {
  'scansioni': {'user_id'},
  'candidati': {'description'},
};

/// Traduce le righe fra la Replica locale e Supabase (ADR-0008). Il
/// registro delle Modifiche in sospeso porta i valori grezzi di SQLite
/// (date ISO in testo, booleani 0/1, liste in JSON, percorsi locali delle
/// immagini); `applica_modifiche` e `cambiamenti_da` parlano JSON con i tipi
/// di Postgres e le chiavi di Storage.
///
/// Le immagini si traducono solo per nome di file: `copertine/<file>` ↔
/// `<collection_id>/<file>` e `scansioni/<file>` ↔ `<user_id>/<file>`. I
/// byte li sposta la coda dei file; un URL resta com'è.
class ConversioneRighe {
  ConversioneRighe(
    AppDatabase db, {
    required this.collectionId,
    required this.userId,
  }) : _tabelle = {
         for (final t in db.allTables)
           if (RegistroModifiche.tabelleReplicate.contains(t.actualTableName))
             t.actualTableName: t,
       };

  final String collectionId;
  final String userId;
  final Map<String, TableInfo<Table, dynamic>> _tabelle;

  TableInfo<Table, dynamic> tabella(String nome) =>
      _tabelle[nome] ?? (throw ArgumentError.value(nome, 'tabella'));

  /// I valori di una voce del registro come li vuole `applica_modifiche`:
  /// senza `id` né colonne solo drift.
  Map<String, Object?> perIlServer(
    String tabella,
    Map<String, Object?> valori,
  ) {
    final colonne = _colonne(tabella);
    return {
      for (final MapEntry(key: nome, value: valore) in valori.entries)
        if (colonne[nome] case final colonna?
            when nome != 'id' &&
                !(_soloDrift[tabella]?.contains(nome) ?? false))
          nome: _versoServer(tabella, colonna, valore),
    };
  }

  Object? _versoServer(String tabella, GeneratedColumn colonna, Object? v) {
    if (v == null) return null;
    final nome = colonna.$name;
    if (colonneImmagine[tabella]?[nome] case final bucket?) {
      return chiaveStorage(bucket, v as String);
    }
    if (_colonneLista[tabella]?.contains(nome) ?? false) {
      return jsonDecode(v as String);
    }
    if (colonna.type == DriftSqlType.bool) return v == 1 || v == true;
    return v;
  }

  /// Una riga di `cambiamenti_da` come valori grezzi per la Replica: solo le
  /// colonne drift, `id` compreso.
  Map<String, Object?> perLaReplica(
    String tabella,
    Map<String, Object?> riga,
  ) {
    final colonne = _colonne(tabella);
    return {
      for (final MapEntry(key: nome, value: valore) in riga.entries)
        if (colonne[nome] case final colonna?
            when !(_soloDrift[tabella]?.contains(nome) ?? false))
          nome: _versoReplica(tabella, colonna, valore),
    };
  }

  Object? _versoReplica(String tabella, GeneratedColumn colonna, Object? v) {
    if (v == null) return null;
    final nome = colonna.$name;
    if (colonneImmagine[tabella]?[nome] case final bucket?) {
      return percorsoLocale(bucket, v as String);
    }
    if (_colonneLista[tabella]?.contains(nome) ?? false) return jsonEncode(v);
    return switch (colonna.type) {
      DriftSqlType.bool => v == true ? 1 : 0,
      // Come le scrive drift per un istante UTC.
      DriftSqlType.dateTime => DateTime.parse(
        v as String,
      ).toUtc().toIso8601String(),
      DriftSqlType.double => (v as num).toDouble(),
      _ => v,
    };
  }

  /// La chiave di Storage del file di una colonna immagine. Un URL resta
  /// com'è.
  String chiaveStorage(BucketImmagine bucket, String valore) {
    if (_remoto(valore)) return valore;
    final prefisso = switch (bucket) {
      BucketImmagine.covers => collectionId,
      BucketImmagine.scansioni => userId,
    };
    return '$prefisso/${p.basename(valore)}';
  }

  /// Il percorso nella Replica, relativo alla cartella del Profilo, del
  /// file con chiave [chiave]. Un URL resta com'è.
  String percorsoLocale(BucketImmagine bucket, String chiave) => _remoto(chiave)
      ? chiave
      : '${bucket.cartellaLocale}/${p.basename(chiave)}';

  Map<String, GeneratedColumn> _colonne(String nome) => {
    for (final c in tabella(nome).$columns) c.$name: c,
  };

  static bool _remoto(String valore) =>
      valore.startsWith('http://') || valore.startsWith('https://');
}
