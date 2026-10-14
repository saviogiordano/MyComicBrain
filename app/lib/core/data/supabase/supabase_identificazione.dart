part of 'supabase_comics_repository.dart';

/// Area Identificazione di [SupabaseComicsRepository] (#196):
/// Identificazione e Candidati (privati all'utente come le Scansioni,
/// ADR-0004), la conferma di un Candidato, la cover presa da una Scansione e
/// i dati letti dal motore di matching.
///
/// La conferma è la RPC transazionale `conferma_candidato`; i valori da
/// scrivere vengono da `conferma_candidato.dart`, condiviso con drift. Le
/// cover finiscono sempre in `covers/` prima della RPC: Storage non sta
/// dentro la transazione, e un oggetto orfano nel bucket privato costa
/// meno di un'Edizione senza cover.
mixin _IdentificazioneSupabase implements ComicsRepository {
  SupabaseClient get _client;
  InvalidazioneTabelle get _invalidazione;
  String get userId;
  CopertinaDownloader get _copertinaDownloader;
  Future<String> collectionId();
  Future<String> _percorsoScansione(String chiave);
  Future<File> _fileInCache(_Bucket bucket, String chiave);

  // --- Identificazione e Candidati ---

  @override
  Future<String> avviaIdentificazione({
    required String scansioneId,
    DateTime? createdAt,
  }) async {
    final riga = await _client
        .from(TabellaSupabase.identificazione.nome)
        .insert({
          'scansione_id': scansioneId,
          'status': StatoIdentificazione.inCorso.name,
          if (createdAt != null) 'created_at': _iso(createdAt),
        })
        .select('id')
        .single();
    _invalidazione.segnala({TabellaSupabase.identificazione});
    return riga['id'] as String;
  }

  @override
  Future<String?> idIdentificazionePerScansione(String scansioneId) async {
    final riga = await _client
        .from(TabellaSupabase.identificazione.nome)
        .select('id')
        .eq('scansione_id', scansioneId)
        .maybeSingle();
    return riga?['id'] as String?;
  }

  @override
  Future<void> riavviaIdentificazione({required String id}) async {
    await _client
        .from(TabellaSupabase.candidati.nome)
        .delete()
        .eq('identificazione_id', id);
    await _client
        .from(TabellaSupabase.identificazione.nome)
        .update({
          'status': StatoIdentificazione.inCorso.name,
          'error_message': null,
          'completed_at': null,
        })
        .eq('id', id);
    _invalidazione.segnala({
      TabellaSupabase.identificazione,
      TabellaSupabase.candidati,
    });
  }

  @override
  Future<String> aggiungiCandidato({
    required String identificazioneId,
    required FonteCandidato source,
    required double punteggio,
    String? edizioneId,
    String? title,
    String? seriesName,
    String? issueNumberLabel,
    String? publisher,
    int? year,
    String? coverImageUrl,
  }) async {
    final riga = await _client
        .from(TabellaSupabase.candidati.nome)
        .insert({
          'identificazione_id': identificazioneId,
          'source': source.name,
          'punteggio': punteggio,
          'edizione_id': edizioneId,
          'title': title,
          'series_name': seriesName,
          'issue_number_label': issueNumberLabel,
          'publisher': publisher,
          'year': year,
          'cover_image_url': coverImageUrl,
        })
        .select('id')
        .single();
    _invalidazione.segnala({TabellaSupabase.candidati});
    return riga['id'] as String;
  }

  @override
  Future<void> completaIdentificazione({
    required String id,
    DateTime? completedAt,
  }) => _aggiornaIdentificazione(id, {
    'status': StatoIdentificazione.completata.name,
    'completed_at': _iso(completedAt ?? DateTime.now()),
  });

  @override
  Future<void> fallisciIdentificazione({
    required String id,
    required String errorMessage,
    DateTime? completedAt,
  }) => _aggiornaIdentificazione(id, {
    'status': StatoIdentificazione.fallita.name,
    'error_message': errorMessage,
    'completed_at': _iso(completedAt ?? DateTime.now()),
  });

  @override
  Future<void> marcaCandidatoScelto({required String id}) async {
    await _client
        .from(TabellaSupabase.candidati.nome)
        .update({'scelto': true})
        .eq('id', id);
    _invalidazione.segnala({TabellaSupabase.candidati});
  }

  /// Stato e Candidati per punteggio decrescente; `pending` finché la
  /// pipeline non ha creato la riga, come su drift. La cover di un
  /// Candidato `interno` è una chiave di `covers/` (da
  /// [catalogoPerMatching]) e si risolve come quella dell'Edizione.
  @override
  Stream<EsitoIdentificazione> watchIdentificazione(String scansioneId) =>
      _invalidazione.osserva(
        {TabellaSupabase.identificazione, TabellaSupabase.candidati},
        () async {
          final riga = await _client
              .from(TabellaSupabase.identificazione.nome)
              .select('status, error_message, candidati(*)')
              .eq('scansione_id', scansioneId)
              .maybeSingle();
          if (riga == null) {
            return (
              stato: StatoIdentificazione.pending,
              errorMessage: null,
              candidati: const <Candidato>[],
            );
          }
          final righe =
              (riga['candidati'] as List).cast<Map<String, dynamic>>().toList()
                ..sort((a, b) {
                  final perPunteggio = (b['punteggio'] as num).compareTo(
                    a['punteggio'] as num,
                  );
                  return perPunteggio != 0
                      ? perPunteggio
                      : (a['id'] as String).compareTo(b['id'] as String);
                });
          return (
            stato: StatoIdentificazione.values.byName(
              riga['status'] as String,
            ),
            errorMessage: riga['error_message'] as String?,
            candidati: [for (final c in righe) await _candidato(c)],
          );
        },
      );

  Future<Candidato> _candidato(Map<String, dynamic> c) async => Candidato(
    id: c['id'] as String,
    source: FonteCandidato.values.byName(c['source'] as String),
    punteggio: (c['punteggio'] as num).toDouble(),
    scelto: c['scelto'] as bool,
    edizioneId: c['edizione_id'] as String?,
    title: c['title'] as String?,
    seriesName: c['series_name'] as String?,
    issueNumberLabel: c['issue_number_label'] as String?,
    publisher: c['publisher'] as String?,
    year: c['year'] as int?,
    coverImageUrl: await risolviCoverImage(c['cover_image_url'] as String?),
  );

  Future<void> _aggiornaIdentificazione(
    String id,
    Map<String, Object?> valori,
  ) async {
    await _client
        .from(TabellaSupabase.identificazione.nome)
        .update(valori)
        .eq('id', id);
    _invalidazione.segnala({TabellaSupabase.identificazione});
  }

  // --- Conferma ---

  @override
  Future<String> confermaCandidato({
    required Candidato candidato,
    required String scansioneId,
  }) async {
    final analisi = await _analisiOrNull(scansioneId);
    final interno = candidato.source == FonteCandidato.interno;
    final prezzo = prezzoCopiaConfermata(analisi);
    final copiaId = await _client.rpc<String>(
      'conferma_candidato',
      params: {
        'target_collection_id': await collectionId(),
        'target_candidato_id': candidato.id,
        'target_scansione_id': scansioneId,
        'target_edizione_id': interno ? candidato.edizioneId : null,
        'descrizione_da_completare': interno
            ? descrizioneDaCompletare(analisi)
            : null,
        // Un candidato `esterno` presuppone un'Analisi Copertina completata
        // (l'Identificazione parte solo dopo), come su drift.
        'nuova_edizione': interno
            ? null
            : await _nuovaEdizione(candidato, analisi!),
        'condizione': condizioneCopiaConfermata.name,
        'prezzo': prezzo?.importo,
        'valuta': prezzo?.valuta.name,
      },
    );
    _invalidazione.segnala({
      TabellaSupabase.candidati,
      TabellaSupabase.opere,
      TabellaSupabase.serie,
      TabellaSupabase.edizioni,
      TabellaSupabase.copie,
    });
    return copiaId;
  }

  Future<Map<String, Object?>> _nuovaEdizione(
    Candidato candidato,
    AnalisiCopertinaTableData analisi,
  ) async {
    final e = nuovaEdizioneDaCandidato(candidato, analisi);
    return {
      'title': e.title,
      'series_name': e.seriesName,
      'publisher': e.publisher,
      'issue_number': e.issueNumber,
      'issue_number_label': e.issueNumberLabel,
      'cover_image': await _coverPerCandidato(candidato),
      'release_date': e.releaseDate,
      'year': e.year,
      'cover_price': e.coverPrice,
      'page_count': e.pageCount,
      'language': e.language,
      'color': e.color,
      'ean': e.ean,
      'description': e.description,
      'printing_type': e.printingType,
      'classificazione': e.classificazione,
    };
  }

  /// La cover ComicVine di un Candidato esterno, scaricata e caricata in
  /// `covers/` così il catalogo non dipende dall'URL remoto. Se il download
  /// fallisce resta l'URL, come su drift: la conferma non fallisce per la
  /// cover.
  Future<String?> _coverPerCandidato(Candidato candidato) async {
    final url = candidato.coverImageUrl;
    if (url == null) return null;
    final scaricata = await _copertinaDownloader.scarica(url);
    if (scaricata == null) return url;
    final file = File(scaricata);
    try {
      return await salvaCoverLocale(file);
    } finally {
      await file.delete();
    }
  }

  Future<AnalisiCopertinaTableData?> _analisiOrNull(String scansioneId) async {
    final esiste = await _client
        .from(TabellaSupabase.analisiCopertina.nome)
        .select('id')
        .eq('scansione_id', scansioneId)
        .maybeSingle();
    return esiste == null ? null : analisiCopertinaPerScansione(scansioneId);
  }

  // --- Cover dalla Scansione ---

  /// Copia l'immagine della Scansione da `scansioni/` a `covers/` e
  /// restituisce la chiave della copia: la cover di un'Edizione vive nella
  /// Collezione (visibile ai membri), la Scansione resta privata
  /// all'utente. La copia è lato server; il file della Scansione, già sul
  /// device, finisce anche nella cache delle cover.
  @override
  Future<String> coverImagePerScansione(String scansioneId) async {
    final riga = await _client
        .from(TabellaSupabase.scansioni.nome)
        .select('image')
        .eq('id', scansioneId)
        .single();
    return _copiaInCover(riga['image'] as String);
  }

  Future<String> _copiaInCover(String chiaveScansione) async {
    final estensione = SupabaseComicsRepository._estensione(chiaveScansione);
    final chiave = '${await collectionId()}/${uuidV4()}.$estensione';
    await _client.storage
        .from(_Bucket.scansioni.nome)
        .copy(chiaveScansione, chiave, destinationBucket: _Bucket.covers.nome);
    final scansione = File(await _percorsoScansione(chiaveScansione));
    if (scansione.existsSync()) {
      final inCache = await _fileInCache(_Bucket.covers, chiave);
      await inCache.parent.create(recursive: true);
      await scansione.copy(inCache.path);
    }
    return chiave;
  }

  /// Per ogni Edizione senza cover, la Scansione della sua prima Copia
  /// scansionata (per id) torna cover, come su drift.
  @override
  Future<int> ripristinaCoverMancantiDaScansione() async {
    final collezione = await collectionId();
    final righe = await _tutteLeRighe(
      () => _client
          .from(TabellaSupabase.edizioni.nome)
          .select('id, copie!inner(id, scansioni!inner(image))')
          .eq('collection_id', collezione)
          .isFilter('cover_image', null),
    );
    var ripristinate = 0;
    for (final e in righe) {
      final copie = (e['copie'] as List).cast<Map<String, dynamic>>().toList()
        ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      final scansione = _unaONessuna(copie.first['scansioni'])!;
      final cover = await _copiaInCover(scansione['image'] as String);
      await _client
          .from(TabellaSupabase.edizioni.nome)
          .update({'cover_image': cover})
          .eq('id', e['id'] as String);
      ripristinate++;
    }
    if (ripristinate > 0) {
      _invalidazione.segnala({TabellaSupabase.edizioni});
    }
    return ripristinate;
  }

  // --- Motore di matching ---

  @override
  Future<List<EdizioneCatalogo>> catalogoPerMatching() async {
    final collezione = await collectionId();
    final righe = await _tutteLeRighe(
      () => _client
          .from(TabellaSupabase.edizioni.nome)
          .select(
            'id, publisher, issue_number, issue_number_label, cover_image, '
            'opere(title), serie(id, name)',
          )
          .eq('collection_id', collezione),
    );
    return [
      for (final e in righe)
        EdizioneCatalogo(
          edizioneId: e['id'] as String,
          title: (e['opere'] as Map<String, dynamic>)['title'] as String,
          serieId: (e['serie'] as Map<String, dynamic>?)?['id'] as String?,
          seriesName: (e['serie'] as Map<String, dynamic>?)?['name'] as String?,
          publisher: e['publisher'] as String?,
          issueNumber: e['issue_number'] as int?,
          issueNumberLabel: e['issue_number_label'] as String?,
          coverImage: e['cover_image'] as String?,
        ),
    ];
  }

  @override
  Future<Map<String, Set<int>>> numeriPossedutiPerSerie() async {
    final collezione = await collectionId();
    final righe = await _tutteLeRighe(
      () => _client
          .from(TabellaSupabase.edizioni.nome)
          .select('serie_id, issue_number, copie!inner(id)')
          .eq('collection_id', collezione)
          .not('serie_id', 'is', null)
          .not('issue_number', 'is', null)
          .inFilter('copie.status', [
            StatoCopia.posseduta.name,
            StatoCopia.prestata.name,
          ]),
    );
    final risultato = <String, Set<int>>{};
    for (final e in righe) {
      risultato
          .putIfAbsent(e['serie_id'] as String, () => <int>{})
          .add(e['issue_number'] as int);
    }
    return risultato;
  }

  /// Tutte le righe di [query], a pagine ordinate per id: una select
  /// PostgREST si ferma a `max_rows`, e il catalogo può superarlo. Si
  /// avanza di quante righe sono arrivate davvero, fino a una pagina vuota,
  /// così il risultato non dipende dal valore di `max_rows`.
  Future<List<Map<String, dynamic>>> _tutteLeRighe(
    PostgrestFilterBuilder<List<Map<String, dynamic>>> Function() query,
  ) async {
    const pagina = 1000;
    final tutte = <Map<String, dynamic>>[];
    while (true) {
      final righe = await query()
          .order('id', ascending: true)
          .range(tutte.length, tutte.length + pagina - 1);
      if (righe.isEmpty) return tutte;
      tutte.addAll(righe);
    }
  }
}
