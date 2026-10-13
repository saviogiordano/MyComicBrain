import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/percorso_locale.dart' as percorso_locale;
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cosa c'è in Modalità locale su questo device e quanto è già nell'account:
/// il testo del prompt di importazione cambia fra account nuovo ed esistente
/// (prototipo #170).
class RiepilogoModalitaLocale {
  const RiepilogoModalitaLocale({
    required this.fumetti,
    required this.scansioniDaCompletare,
    required this.fumettiNellAccount,
  });

  /// Le Copie in drift.
  final int fumetti;

  /// Le Scansioni non ancora risolte in una Copia.
  final int scansioniDaCompletare;

  final int fumettiNellAccount;
}

enum FaseImportazione { cover, scansioni, catalogo }

class AvanzamentoImportazione {
  const AvanzamentoImportazione(this.fase, this.fatti, this.totale);

  final FaseImportazione fase;
  final int fatti;
  final int totale;

  double get frazione => totale == 0 ? 0 : fatti / totale;
}

class EsitoImportazione {
  const EsitoImportazione({required this.fumettiNellAccount});

  /// Le Copie della Collezione dopo l'importazione.
  final int fumettiNellAccount;
}

/// L'importazione dei dati della Modalità locale nell'account (ADR-0005),
/// vista dal flusso di importazione: un seam per poterlo provare senza
/// Supabase. L'implementazione reale è [ImportazioneModalitaLocale].
abstract interface class ImportatoreModalitaLocale {
  Future<RiepilogoModalitaLocale> riepilogo();

  /// Importa tutto con lo stesso [importId] a ogni tentativo e, a successo,
  /// svuota drift. Un errore lascia drift intatto: un nuovo tentativo con
  /// lo stesso id non duplica nulla.
  Future<EsitoImportazione> importa(
    String importId, {
    void Function(AvanzamentoImportazione)? avanzamento,
  });

  /// Rifiuto dell'importazione: drift si svuota senza importare.
  Future<void> scartaDatiLocali();
}

const _bucketCover = 'covers';
const _bucketScansioni = 'scansioni';

/// Cartelle dei file locali (vedi `CopertinaDownloader`, `ScansioneStorage`)
/// rimosse con drift: dopo l'importazione non le legge più nessuno.
const _cartelleFileLocali = ['copertine', 'scansioni', 'scansioni_grezze'];

/// Le colonne lista di `analisi_copertina`: in drift sono JSON in un testo,
/// in Postgres `text[]`.
const _colonneLista = {'characters', 'cover_style_tags', 'visual_element_tags'};

/// Implementazione di ADR-0007: legge drift direttamente (non passa da
/// `ComicsRepository`), carica prima le immagini su Storage con chiavi
/// deterministiche per `importId`, poi invoca la RPC transazionale
/// `importa_modalita_locale`, idempotente sullo stesso id.
class ImportazioneModalitaLocale implements ImportatoreModalitaLocale {
  ImportazioneModalitaLocale({
    required AppDatabase db,
    required SupabaseClient client,
    required this.userId,
    required Future<Directory> Function() baseDirectory,
  }) : _db = db,
       _client = client,
       _baseDirectory = baseDirectory;

  final AppDatabase _db;
  final SupabaseClient _client;
  final String userId;
  final Future<Directory> Function() _baseDirectory;

  @override
  Future<RiepilogoModalitaLocale> riepilogo() async {
    final fumetti = await _db.copie.count().getSingle();
    final scansioni = await _scansioniDaCompletare();
    return RiepilogoModalitaLocale(
      fumetti: fumetti,
      scansioniDaCompletare: scansioni.length,
      fumettiNellAccount: await _fumettiNellAccount(),
    );
  }

  Future<int> _fumettiNellAccount() async =>
      _client.from('copie').count().eq('collection_id', await _collectionId());

  Future<String> _collectionId() async {
    final riga = await _client
        .from('collection_members')
        .select('collection_id')
        .eq('user_id', userId)
        .eq('role', 'owner')
        .single();
    return riga['collection_id'] as String;
  }

  Future<List<ScansioniData>> _scansioniDaCompletare() async {
    final risolte = _db.selectOnly(_db.copie)
      ..addColumns([_db.copie.scansioneId])
      ..where(_db.copie.scansioneId.isNotNull());
    return (_db.select(
      _db.scansioni,
    )..where((s) => s.id.isNotInQuery(risolte))).get();
  }

  @override
  Future<EsitoImportazione> importa(
    String importId, {
    void Function(AvanzamentoImportazione)? avanzamento,
  }) async {
    final collectionId = await _collectionId();
    final base = await _baseDirectory();
    final edizioni = await _db.select(_db.edizioni).get();
    final serie = await _db.select(_db.serieTable).get();
    final scansioni = await _scansioniDaCompletare();

    // Una chiave per file locale distinto: più Edizioni possono condividere
    // la stessa immagine (es. la cover presa dalla Scansione).
    final coverLocali = {
      for (final cover in [
        ...edizioni.map((e) => e.coverImage),
        ...serie.map((s) => s.coverImage),
      ])
        if (cover != null && !_remoto(cover)) cover,
    }.toList()..sort();
    final totale = coverLocali.length + scansioni.length + 1;
    var fatti = 0;
    void avanza(FaseImportazione fase) =>
        avanzamento?.call(AvanzamentoImportazione(fase, fatti, totale));

    avanza(FaseImportazione.cover);
    final chiaviCover = <String, String?>{};
    for (final (indice, cover) in coverLocali.indexed) {
      chiaviCover[cover] = await _carica(
        bucket: _bucketCover,
        percorso: await percorso_locale.risolvi(cover, () async => base),
        chiaveSenzaEstensione: '$collectionId/importazione-$importId-$indice',
      );
      fatti++;
      avanza(FaseImportazione.cover);
    }

    avanza(FaseImportazione.scansioni);
    final chiaviScansioni = <int, String>{};
    for (final scansione in scansioni) {
      final chiave = await _carica(
        bucket: _bucketScansioni,
        percorso: await percorso_locale.risolvi(
          scansione.image,
          () async => base,
        ),
        chiaveSenzaEstensione: '$userId/importazione-$importId-${scansione.id}',
      );
      if (chiave != null) chiaviScansioni[scansione.id] = chiave;
      fatti++;
      avanza(FaseImportazione.scansioni);
    }

    avanza(FaseImportazione.catalogo);
    final payload = await _payload(
      edizioni: edizioni,
      serie: serie,
      scansioni: scansioni,
      chiaviCover: chiaviCover,
      chiaviScansioni: chiaviScansioni,
    );
    final esito = await _client.rpc<Map<String, dynamic>>(
      'importa_modalita_locale',
      params: {'payload': payload, 'import_id': importId},
    );
    fatti++;
    avanza(FaseImportazione.catalogo);

    await scartaDatiLocali();
    return EsitoImportazione(
      fumettiNellAccount: (esito['copie_collezione'] as num).toInt(),
    );
  }

  /// Carica il file in upsert (un nuovo tentativo sovrascrive lo stesso
  /// oggetto) e restituisce la chiave; `null` se il file locale non c'è più:
  /// una cover persa non deve bloccare l'importazione dell'intera
  /// collezione.
  Future<String?> _carica({
    required String bucket,
    required String percorso,
    required String chiaveSenzaEstensione,
  }) async {
    final file = File(percorso);
    if (!file.existsSync()) return null;
    final estensione = switch (p
        .extension(percorso)
        .replaceFirst('.', '')
        .toLowerCase()) {
      'png' => 'png',
      'webp' => 'webp',
      _ => 'jpg',
    };
    final chiave = '$chiaveSenzaEstensione.$estensione';
    await _client.storage
        .from(bucket)
        .upload(
          chiave,
          file,
          fileOptions: FileOptions(
            upsert: true,
            contentType: estensione == 'jpg'
                ? 'image/jpeg'
                : 'image/$estensione',
          ),
        );
    return chiave;
  }

  /// Le righe drift con i nomi di colonna SQL, che coincidono con quelli
  /// Postgres (vedi `supabase/migrations/20260925090100_catalogo.sql`).
  Future<Map<String, Object?>> _payload({
    required List<EdizioniData> edizioni,
    required List<SerieTableData> serie,
    required List<ScansioniData> scansioni,
    required Map<String, String?> chiaviCover,
    required Map<int, String> chiaviScansioni,
  }) async {
    String? cover(String? valore) =>
        valore == null || _remoto(valore) ? valore : chiaviCover[valore];

    final identificazioni = await (_db.select(
      _db.identificazioneTable,
    )..where((i) => i.scansioneId.isIn(chiaviScansioni.keys))).get();
    final idIdentificazioni = identificazioni.map((i) => i.id);

    return {
      'opere': _righe(await _db.select(_db.opere).get()),
      'serie': [
        for (final riga in serie)
          {..._riga(riga), 'cover_image': cover(riga.coverImage)},
      ],
      'edizioni': [
        for (final riga in edizioni)
          {..._riga(riga), 'cover_image': cover(riga.coverImage)},
      ],
      'copie': _righe(await _db.select(_db.copie).get()),
      'valore_stimato': _righe(
        await _db.select(_db.valoreStimatoTable).get(),
      ),
      'creator': _righe(await _db.select(_db.creator).get()),
      'comic_creator': _righe(await _db.select(_db.comicCreator).get()),
      'tag': _righe(await _db.select(_db.tagTable).get()),
      'edizione_tag': _righe(await _db.select(_db.edizioneTag).get()),
      'character': _righe(await _db.select(_db.character).get()),
      'comic_character': _righe(await _db.select(_db.comicCharacter).get()),
      'edizione_genere': _righe(await _db.select(_db.edizioneGenere).get()),
      // Senza la colonna drift `user_id` (un intero mai usato): in Postgres
      // è l'uuid dell'utente.
      'scansioni': [
        for (final riga in scansioni)
          if (chiaviScansioni[riga.id] case final chiave?)
            {
              'id': riga.id,
              'image': chiave,
              'created_at': _valore(riga.createdAt),
            },
      ],
      'analisi_copertina': _righe(
        await (_db.select(
          _db.analisiCopertinaTable,
        )..where((a) => a.scansioneId.isIn(chiaviScansioni.keys))).get(),
      ),
      'identificazione': _righe(identificazioni),
      'candidati': _righe(
        await (_db.select(
          _db.candidatiTable,
        )..where((c) => c.identificazioneId.isIn(idIdentificazioni))).get(),
      ),
    };
  }

  static List<Map<String, Object?>> _righe(
    Iterable<Insertable<Object?>> righe,
  ) => [for (final riga in righe) _riga(riga)];

  static Map<String, Object?> _riga(Insertable<Object?> riga) => {
    for (final MapEntry(key: colonna, value: espressione)
        in riga.toColumns(false).entries)
      colonna: _colonneLista.contains(colonna)
          ? jsonDecode((espressione as Variable).value! as String)
          : _valore((espressione as Variable).value),
  };

  static Object? _valore(Object? valore) =>
      valore is DateTime ? valore.toUtc().toIso8601String() : valore;

  static bool _remoto(String valore) =>
      valore.startsWith('http://') || valore.startsWith('https://');

  /// Svuota drift in una transazione (figli prima dei padri) e poi, best
  /// effort, i file locali: la Modalità locale è consumata.
  @override
  Future<void> scartaDatiLocali() async {
    await _db.transaction(() async {
      for (final tabella in <TableInfo<Table, Object?>>[
        _db.messaggioTable,
        _db.conversazioneTable,
        _db.candidatiTable,
        _db.identificazioneTable,
        _db.analisiCopertinaTable,
        _db.valoreStimatoTable,
        _db.copie,
        _db.scansioni,
        _db.edizioneGenere,
        _db.comicCharacter,
        _db.character,
        _db.edizioneTag,
        _db.tagTable,
        _db.comicCreator,
        _db.creator,
        _db.edizioni,
        _db.serieTable,
        _db.opere,
      ]) {
        await _db.delete(tabella).go();
      }
    });
    final base = await _baseDirectory();
    for (final cartella in _cartelleFileLocali) {
      try {
        await Directory(p.join(base.path, cartella)).delete(recursive: true);
      } on FileSystemException {
        // Già assente o non rimovibile: drift è vuoto, basta questo.
      }
    }
  }
}
